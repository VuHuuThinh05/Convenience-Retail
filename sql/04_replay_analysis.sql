set hive.exec.mode.local.auto=true;
USE retail_dw;

-- Q1. Doanh thu theo nam, quy, thang (JOIN dim_time khong trung khoa)
SELECT '=== Q1: DOANH THU THEO THOI GIAN ===';
SELECT
    t.trans_year,
    t.trans_quarter,
    t.trans_month,
    COUNT(f.transaction_id) AS total_transactions,
    SUM(f.total_items) AS total_items,
    ROUND(SUM(f.total_cost), 2) AS total_revenue
FROM fact_sales f
JOIN dim_time t ON f.date_str = t.date_str
GROUP BY t.trans_year, t.trans_quarter, t.trans_month
ORDER BY t.trans_year, t.trans_month;

-- Q2. Doanh thu theo phuong thuc thanh toan
SELECT '=== Q2: PHUONG THUC THANH TOAN ===';
SELECT
    payment_method,
    COUNT(*) AS total_transactions,
    ROUND(SUM(total_cost), 2) AS total_revenue,
    ROUND(AVG(total_cost), 2) AS avg_order_value
FROM fact_sales
GROUP BY payment_method
ORDER BY total_revenue DESC;

-- Q3. Doanh thu theo thanh pho & khung gio
SELECT '=== Q3: THANH PHO VA KHUNG GIO ===';
SELECT
    city,
    time_of_day,
    COUNT(*) AS total_transactions,
    ROUND(SUM(total_cost), 2) AS total_revenue
FROM fact_sales
GROUP BY city, time_of_day
ORDER BY city, total_revenue DESC;

-- Q4. Doanh thu theo nhom khach hang (JOIN bang customer_id tranh trung ten)
SELECT '=== Q4: NHOM KHACH HANG ===';
SELECT
    c.customer_category,
    COUNT(f.transaction_id) AS total_transactions,
    ROUND(SUM(f.total_cost), 2) AS total_revenue,
    ROUND(AVG(f.total_cost), 2) AS avg_order_value
FROM fact_sales f
JOIN dim_customer c ON f.customer_id = c.customer_id
GROUP BY c.customer_category
ORDER BY total_revenue DESC;

-- Q5. So sanh khach hang Thanh vien (Member) vs Khong thanh vien
SELECT '=== Q5: THANH VIEN (MEMBER) ===';
SELECT
    c.member,
    COUNT(f.transaction_id) AS total_transactions,
    ROUND(SUM(f.total_cost), 2) AS total_revenue,
    ROUND(AVG(f.total_cost), 2) AS avg_order_value
FROM fact_sales f
JOIN dim_customer c ON f.customer_id = c.customer_id
GROUP BY c.member
ORDER BY total_revenue DESC;

-- Q6. Hieu qua chuong trinh khuyen mai (Promotion)
SELECT '=== Q6: KHUYEN MAI ===';
SELECT
    promotion,
    COUNT(*) AS total_transactions,
    ROUND(SUM(total_cost), 2) AS total_revenue,
    ROUND(AVG(total_cost), 2) AS avg_order_value
FROM fact_sales
GROUP BY promotion
ORDER BY total_revenue DESC;

-- Q7. Doanh thu theo mua (Season)
SELECT '=== Q7: DOANH THU THEO MUA ===';
SELECT
    t.season,
    COUNT(f.transaction_id) AS total_transactions,
    ROUND(SUM(f.total_cost), 2) AS total_revenue
FROM fact_sales f
JOIN dim_time t ON f.date_str = t.date_str
GROUP BY t.season
ORDER BY total_revenue DESC;

-- Q8. Top 15 san pham ban chay nhat
SELECT '=== Q8: TOP 15 SAN PHAM BAN CHAY ===';
SELECT
    product_id,
    product_name,
    COUNT(*) AS times_purchased
FROM fact_transaction_items
GROUP BY product_id, product_name
ORDER BY times_purchased DESC
LIMIT 15;

-- Q9. Market Basket Analysis (Cap san pham mua cung nhau + Support, Confidence, Lift)
SELECT '=== Q9: MARKET BASKET ANALYSIS (TOP 20 CAP SAN PHAM) ===';
WITH total_tx AS (
    SELECT COUNT(DISTINCT transaction_id) AS n_tx FROM fact_transaction_items
),
item_counts AS (
    SELECT product_name, COUNT(DISTINCT transaction_id) AS item_tx
    FROM fact_transaction_items
    GROUP BY product_name
),
pair_counts AS (
    SELECT
        a.product_name AS item_a,
        b.product_name AS item_b,
        COUNT(DISTINCT a.transaction_id) AS pair_tx
    FROM fact_transaction_items a
    JOIN fact_transaction_items b
      ON a.transaction_id = b.transaction_id
     AND a.product_name < b.product_name
    GROUP BY a.product_name, b.product_name
)
SELECT
    p.item_a,
    p.item_b,
    p.pair_tx AS co_occurrence,
    ROUND(p.pair_tx / t.n_tx, 5) AS support,
    ROUND(p.pair_tx / ia.item_tx, 4) AS confidence_a_to_b,
    ROUND((p.pair_tx / t.n_tx) / ((ia.item_tx / t.n_tx) * (ib.item_tx / t.n_tx)), 4) AS lift
FROM pair_counts p
CROSS JOIN total_tx t
JOIN item_counts ia ON p.item_a = ia.product_name
JOIN item_counts ib ON p.item_b = ib.product_name
ORDER BY co_occurrence DESC
LIMIT 20;
