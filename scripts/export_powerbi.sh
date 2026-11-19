#!/usr/bin/env bash
set -euo pipefail

EXPORT_DIR="$1"

export_query() {
    local filename="$1"
    local query="$2"
    echo "Dang xuat $filename..."
    hive -S -e "
    set hive.cli.print.header=true;
    set hive.exec.mode.local.auto=true;
    set hive.auto.convert.join=false;
    USE retail_dw;
    $query
    " | tr '\t' ',' > "$EXPORT_DIR/$filename"
}

# 1. Xuat cac bang Star Schema (Fact & Dimension) de ve Dashboard tuong tac
export_query "fact_sales.csv" "SELECT * FROM fact_sales;"
export_query "fact_transaction_items.csv" "SELECT * FROM fact_transaction_items;"
export_query "dim_time.csv" "SELECT * FROM dim_time;"
export_query "dim_customer.csv" "SELECT * FROM dim_customer;"
export_query "dim_product.csv" "SELECT * FROM dim_product;"

# 2. Xuat cac bang tong hop Q1 - Q9 de doi chieu & ve bieu do nhanh
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

export_query "q7_revenue_by_season.csv" "
SELECT t.season,
       COUNT(f.transaction_id) AS total_transactions,
       ROUND(SUM(f.total_cost), 2) AS total_revenue
FROM fact_sales f
JOIN dim_time t ON f.date_str = t.date_str
GROUP BY t.season
ORDER BY total_revenue DESC;"

export_query "q8_top_products.csv" "
SELECT product_id, product_name,
       COUNT(*) AS times_purchased
FROM fact_transaction_items
GROUP BY product_id, product_name
ORDER BY times_purchased DESC
LIMIT 20;"

export_query "q9_market_basket_top20.csv" "
SELECT p.item_a, p.item_b,
       p.pair_tx AS co_occurrence,
       ROUND(p.pair_tx / 18531.0, 5) AS support,
       ROUND(p.pair_tx / ia.item_tx, 4) AS confidence_a_to_b,
       ROUND((p.pair_tx / 18531.0) / ((ia.item_tx / 18531.0) * (ib.item_tx / 18531.0)), 4) AS lift
FROM (
    SELECT a.product_name AS item_a, b.product_name AS item_b,
           COUNT(DISTINCT a.transaction_id) AS pair_tx
    FROM fact_transaction_items a
    JOIN fact_transaction_items b
      ON a.transaction_id = b.transaction_id AND a.product_name < b.product_name
    GROUP BY a.product_name, b.product_name
) p
JOIN (SELECT product_name, COUNT(DISTINCT transaction_id) AS item_tx FROM fact_transaction_items GROUP BY product_name) ia ON p.item_a = ia.product_name
JOIN (SELECT product_name, COUNT(DISTINCT transaction_id) AS item_tx FROM fact_transaction_items GROUP BY product_name) ib ON p.item_b = ib.product_name
ORDER BY co_occurrence DESC
LIMIT 20;"

echo "Hoan tat xuat toan bo file CSV tai: $EXPORT_DIR"
