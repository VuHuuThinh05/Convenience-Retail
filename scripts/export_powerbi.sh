#!/usr/bin/env bash
set -euo pipefail

EXPORT_DIR="${1:-data/powerbi_export}"
mkdir -p "$EXPORT_DIR"
EXPORT_DIR="$(cd "$EXPORT_DIR" && pwd -P)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
STAGING_DIR="$(mktemp -d "$EXPORT_DIR/.export.XXXXXXXX")"
trap 'rm -rf -- "$STAGING_DIR"' EXIT
EXPORTED_FILES=()

export_query() {
    local filename="$1"
    local query="$2"
    local raw="$STAGING_DIR/$filename.tsv"
    echo "Dang xuat $filename..."
    bash "$SCRIPT_DIR/hive_cli.sh" -S -e "
    set hive.cli.print.header=true;
    set hive.exec.mode.local.auto=false;
    set hive.auto.convert.join=false;
    USE retail_dw;
    $query
    " > "$raw"
    python3 - "$raw" "$STAGING_DIR/$filename" <<'PY'
import csv
import sys

with open(sys.argv[1], encoding="utf-8", newline="") as source:
    rows = list(csv.reader(source, delimiter="\t"))
if len(rows) < 2 or not rows[0]:
    raise SystemExit(f"Hive khong tra ve du lieu: {sys.argv[1]}")
rows[0] = [name.rsplit(".", 1)[-1] for name in rows[0]]
with open(sys.argv[2], "w", encoding="utf-8", newline="") as target:
    writer = csv.writer(target)
    writer.writerows(rows)
PY
    EXPORTED_FILES+=("$filename")
}

# 1. Xuat cac bang Star Schema (Fact & Dimension) de ve Dashboard tuong tac
export_query "fact_sales.csv" "SELECT * FROM fact_sales;"
export_query "fact_transaction_items.csv" "SELECT * FROM fact_transaction_items;"
export_query "dim_time.csv" "SELECT * FROM dim_time;"
export_query "dim_customer.csv" "SELECT * FROM dim_customer;"
export_query "dim_product.csv" "SELECT * FROM dim_product;"

# 2. Xuat cac bang tong hop Q1-Q6, Q8-Q9 de doi chieu & ve bieu do nhanh
export_query "q1_revenue_by_time.csv" "
SELECT t.trans_year, t.trans_quarter, t.trans_month,
       COUNT(f.transaction_id) AS total_transactions,
       SUM(f.total_items) AS total_items,
       ROUND(SUM(f.total_cost), 2) AS total_revenue
FROM fact_sales f
JOIN dim_time t ON f.date_str = t.date_str
GROUP BY t.trans_year, t.trans_quarter, t.trans_month
ORDER BY t.trans_year, t.trans_month;"

export_query "q2_revenue_by_payment.csv" "
SELECT payment_method,
       COUNT(*) AS total_transactions,
       ROUND(SUM(total_cost), 2) AS total_revenue,
       ROUND(AVG(total_cost), 2) AS avg_order_value
FROM fact_sales
GROUP BY payment_method
ORDER BY total_revenue DESC;"

export_query "q3_revenue_by_city_time.csv" "
SELECT city, time_of_day,
       COUNT(*) AS total_transactions,
       ROUND(SUM(total_cost), 2) AS total_revenue
FROM fact_sales
GROUP BY city, time_of_day
ORDER BY city, total_revenue DESC;"

export_query "q4_revenue_by_customer_category.csv" "
SELECT c.customer_category,
       COUNT(f.transaction_id) AS total_transactions,
       ROUND(SUM(f.total_cost), 2) AS total_revenue,
       ROUND(AVG(f.total_cost), 2) AS avg_order_value
FROM fact_sales f
JOIN dim_customer c ON f.customer_id = c.customer_id
GROUP BY c.customer_category
ORDER BY total_revenue DESC;"

export_query "q5_revenue_by_member.csv" "
SELECT c.member,
       COUNT(f.transaction_id) AS total_transactions,
       ROUND(SUM(f.total_cost), 2) AS total_revenue,
       ROUND(AVG(f.total_cost), 2) AS avg_order_value
FROM fact_sales f
JOIN dim_customer c ON f.customer_id = c.customer_id
GROUP BY c.member
ORDER BY total_revenue DESC;"

export_query "q6_revenue_by_promotion.csv" "
SELECT promotion,
       COUNT(*) AS total_transactions,
       ROUND(SUM(total_cost), 2) AS total_revenue,
       ROUND(AVG(total_cost), 2) AS avg_order_value
FROM fact_sales
GROUP BY promotion
ORDER BY total_revenue DESC;"

export_query "q8_top_products.csv" "
SELECT product_id, product_name,
       COUNT(*) AS times_purchased
FROM fact_transaction_items
GROUP BY product_id, product_name
ORDER BY times_purchased DESC
LIMIT 20;"

export_query "q9_market_basket_top20.csv" "
WITH total_tx AS (
    SELECT COUNT(DISTINCT transaction_id) AS n_tx FROM fact_sales
),
item_counts AS (
    SELECT product_name, COUNT(DISTINCT transaction_id) AS item_tx
    FROM fact_transaction_items GROUP BY product_name
),
pair_counts AS (
    SELECT a.product_name AS item_a, b.product_name AS item_b,
           COUNT(DISTINCT a.transaction_id) AS pair_tx
    FROM fact_transaction_items a
    JOIN fact_transaction_items b
      ON a.transaction_id = b.transaction_id AND a.product_name < b.product_name
    GROUP BY a.product_name, b.product_name
)
SELECT p.item_a, p.item_b,
       p.pair_tx AS co_occurrence,
       ROUND(p.pair_tx / t.n_tx, 5) AS support,
       ROUND(p.pair_tx / ia.item_tx, 4) AS confidence_a_to_b,
       ROUND((p.pair_tx / t.n_tx) / ((ia.item_tx / t.n_tx) * (ib.item_tx / t.n_tx)), 4) AS lift
FROM pair_counts p
CROSS JOIN total_tx t
JOIN item_counts ia ON p.item_a = ia.product_name
JOIN item_counts ib ON p.item_b = ib.product_name
ORDER BY co_occurrence DESC
LIMIT 20;"

for filename in "${EXPORTED_FILES[@]}"; do
    mv -- "$STAGING_DIR/$filename" "$EXPORT_DIR/$filename"
done
echo "Hoan tat xuat toan bo file CSV tai: $EXPORT_DIR"
