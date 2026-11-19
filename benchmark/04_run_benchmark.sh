#!/bin/bash
mkdir -p results/benchmark
OUT="results/benchmark/benchmark_results.csv"
ERR_LOG="results/benchmark/benchmark_error.log"
> "$ERR_LOG"

echo "run_id,query_id,format,partitioned,run_number,duration_ms,status" > "$OUT"

DB_NAME="retail_dw"
TABLES=("fact_sales_text_nopan" "fact_sales_orc_nopan" "fact_sales_text_pan" "fact_sales_orc_pan")
FORMATS=("TextFile" "ORC" "TextFile" "ORC")
PARTS=("No" "No" "Yes" "Yes")

RUNS=3

for i in "${!TABLES[@]}"; do
    tbl="${TABLES[$i]}"
    fmt="${FORMATS[$i]}"
    part="${PARTS[$i]}"
    
    queries=(
        "Q_A:USE $DB_NAME; SELECT COUNT(*), SUM(total_cost) FROM $tbl;"
        "Q_B:USE $DB_NAME; SELECT SUBSTR(date_str, 1, 7), SUM(total_cost) FROM $tbl GROUP BY SUBSTR(date_str, 1, 7);"
        "Q_C:USE $DB_NAME; SELECT COUNT(*), SUM(total_cost) FROM $tbl WHERE date_str >= '2022-01-01' AND date_str <= '2022-06-30';"
        "Q_D:USE $DB_NAME; SELECT payment_method, SUM(total_cost) FROM $tbl GROUP BY payment_method;"
    )

    for q in "${queries[@]}"; do
        qid="${q%%:*}"
        sql="${q#*:}"
        
        for r in $(seq 1 $RUNS); do
            start_time=$(date +%s%N)
            hive -e "$sql" >> "$ERR_LOG" 2>&1
            exit_code=$?
            end_time=$(date +%s%N)
            
            duration_ms=$(( (end_time - start_time) / 1000000 ))
            status="SUCCESS"
            if [ $exit_code -ne 0 ]; then
                status="FAIL"
                duration_ms=0
            fi
            
            echo "1,$qid,$fmt,$part,$r,$duration_ms,$status" >> "$OUT"
            echo "Thực thi: Table=$tbl | Query=$qid | Run=$r -> ${duration_ms}ms ($status)"
        done
    done
done
