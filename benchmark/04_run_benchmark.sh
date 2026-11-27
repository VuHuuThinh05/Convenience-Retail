#!/usr/bin/env bash
set -euo pipefail

# Run after: hive -f benchmark/02_create_tables.sql
# Measures Hive CLI wall time (including process startup) on the original
# transaction data. The four variants must agree before any result is saved.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
command -v hive >/dev/null || { echo 'Missing hive CLI' >&2; exit 1; }
command -v hdfs >/dev/null || { echo 'Missing hdfs CLI' >&2; exit 1; }

mkdir -p "$PROJECT_DIR/results/benchmark"
OUT="$PROJECT_DIR/results/benchmark/benchmark_results.csv"
VALIDATION="$PROJECT_DIR/results/benchmark/benchmark_validation.csv"
ERR_LOG="$PROJECT_DIR/results/benchmark/benchmark_error.log"
# Hive CLI's embedded Derby metastore is relative to its working directory.
# In this WSL setup it is initialized in the Linux home directory.
cd "$HOME"
DB_NAME='retail_dw'
TABLES=(fact_sales_text_nopan fact_sales_orc_nopan fact_sales_text_pan fact_sales_orc_pan)
FORMATS=(TextFile ORC TextFile ORC)
PARTS=(No No Yes Yes)
RUNS=3
RUN_ID="$(date +%Y%m%d_%H%M%S)"
TEMP_OUTPUT="$(mktemp)"
TEMP_VALIDATION="$(mktemp)"
trap 'rm -f "$TEMP_OUTPUT" "$TEMP_VALIDATION"' EXIT
: > "$ERR_LOG"

hive_value() {
    hive -S -e "USE $DB_NAME; $1" 2>>"$ERR_LOG" | tail -n 1
}

same_amount() {
    awk -v a="$1" -v b="$2" 'BEGIN {d=a-b; if (d<0) d=-d; exit (d<=0.005 ? 0 : 1)}'
}

source_value="$(hive_value 'SELECT COUNT(*), SUM(CAST(total_cost AS DECIMAL(12,2))) FROM fact_sales;')"
IFS=$'\t' read -r source_count source_revenue <<< "$source_value"
[[ "$source_count" =~ ^[0-9]+$ && "$source_count" -gt 0 ]] || { echo 'Invalid source fact_sales count' >&2; exit 1; }
[[ "$source_revenue" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo 'Invalid source revenue' >&2; exit 1; }

source_range="$(hive_value "SELECT COUNT(*), SUM(CAST(total_cost AS DECIMAL(12,2))) FROM fact_sales WHERE date_str >= '2022-01-01' AND date_str < '2022-07-01';")"
IFS=$'\t' read -r source_range_count source_range_revenue <<< "$source_range"
[[ "$source_range_count" =~ ^[0-9]+$ && "$source_range_count" -gt 0 ]] || { echo 'Date-range query returned no rows' >&2; exit 1; }
[[ "$source_range_revenue" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo 'Invalid date-range revenue' >&2; exit 1; }

echo 'run_id,table_name,format,partitioned,row_count,total_revenue,range_row_count,range_revenue,hdfs_size_bytes' > "$TEMP_VALIDATION"
for i in "${!TABLES[@]}"; do
    tbl="${TABLES[$i]}"
    part="${PARTS[$i]}"
    whole="$(hive_value "SELECT COUNT(*), SUM(total_cost) FROM $tbl;")"
    IFS=$'\t' read -r row_count total_revenue <<< "$whole"
    [[ "$row_count" == "$source_count" ]] && same_amount "$total_revenue" "$source_revenue" || {
        echo "$tbl differs from source fact_sales (count/revenue)" >&2; exit 1;
    }

    predicate="date_str >= '2022-01-01' AND date_str < '2022-07-01'"
    if [[ "$part" == Yes ]]; then
        predicate="$predicate AND month_str BETWEEN '2022-01' AND '2022-06'"
    fi
    selected="$(hive_value "SELECT COUNT(*), SUM(total_cost) FROM $tbl WHERE $predicate;")"
    IFS=$'\t' read -r range_count range_revenue <<< "$selected"
    [[ "$range_count" == "$source_range_count" ]] && same_amount "$range_revenue" "$source_range_revenue" || {
        echo "$tbl differs from source in the Q_C date range" >&2; exit 1;
    }

    location="$(hive -S -e "USE $DB_NAME; DESCRIBE FORMATTED $tbl;" 2>>"$ERR_LOG" | awk '$1 == "Location:" {print $2; exit}')"
    [[ -n "$location" ]] || { echo "Cannot find HDFS location for $tbl" >&2; exit 1; }
    size="$(hdfs dfs -du -s "$location" 2>>"$ERR_LOG" | awk 'NR==1 {print $1}')"
    [[ "$size" =~ ^[0-9]+$ ]] || { echo "Cannot measure HDFS size for $tbl" >&2; exit 1; }
    echo "$RUN_ID,$tbl,${FORMATS[$i]},$part,$row_count,$total_revenue,$range_count,$range_revenue,$size" >> "$TEMP_VALIDATION"
done

mv "$TEMP_VALIDATION" "$VALIDATION"
echo 'run_id,query_id,format,partitioned,run_number,duration_ms,status' > "$OUT"
failures=0

# Rotate table order between rounds to reduce time-of-run bias.
for round in $(seq 1 "$RUNS"); do
    for offset in 0 1 2 3; do
        i=$(( (offset + round - 1) % 4 ))
        tbl="${TABLES[$i]}"
        part="${PARTS[$i]}"
        date_filter="date_str >= '2022-01-01' AND date_str < '2022-07-01'"
        if [[ "$part" == Yes ]]; then
            date_filter="$date_filter AND month_str BETWEEN '2022-01' AND '2022-06'"
        fi
        queries=(
            "Q_A:SELECT COUNT(*), SUM(total_cost) FROM $tbl;"
            "Q_B:SELECT SUBSTR(date_str, 1, 7), SUM(total_cost) FROM $tbl GROUP BY SUBSTR(date_str, 1, 7);"
            "Q_C:SELECT COUNT(*), SUM(total_cost) FROM $tbl WHERE $date_filter;"
            "Q_D:SELECT payment_method, SUM(total_cost) FROM $tbl GROUP BY payment_method;"
        )
        for q in "${queries[@]}"; do
            qid="${q%%:*}"
            sql="${q#*:}"
            start_ns="$(date +%s%N)"
            status=SUCCESS
            if ! hive -S -e "USE $DB_NAME; $sql" > "$TEMP_OUTPUT" 2>> "$ERR_LOG" || [[ ! -s "$TEMP_OUTPUT" ]]; then
                status=FAIL
                failures=$((failures + 1))
            fi
            end_ns="$(date +%s%N)"
            duration_ms=$(( (end_ns - start_ns) / 1000000 ))
            echo "$RUN_ID,$qid,${FORMATS[$i]},$part,$round,$duration_ms,$status" >> "$OUT"
            echo "$tbl $qid run=$round ${duration_ms}ms $status"
        done
    done
done

if (( failures > 0 )); then
    echo "$failures benchmark queries failed; inspect $ERR_LOG" >&2
    exit 1
fi
echo "Benchmark complete. Validation: $VALIDATION; measurements: $OUT"
