SET hive.execution.engine=mr;
SET hive.exec.mode.local.auto=false;
SET hive.auto.convert.join=false;

CREATE DATABASE IF NOT EXISTS retail_dw;
USE retail_dw;

DROP TABLE IF EXISTS stg_products;
DROP TABLE IF EXISTS stg_transactions;
DROP TABLE IF EXISTS stg_transaction_items;
DROP TABLE IF EXISTS dim_time;
DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS dim_product;
DROP TABLE IF EXISTS dim_promotion;
DROP TABLE IF EXISTS dim_payment;
DROP TABLE IF EXISTS fact_sales;
DROP TABLE IF EXISTS fact_transaction_items;

-- 1. Tạo 3 bảng Staging EXTERNAL trỏ thẳng vào dữ liệu Sqoop trên HDFS (phân tách Ctrl-A '\001')
CREATE EXTERNAL TABLE stg_products (
    product_id INT,
    product_name STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\001'
STORED AS TEXTFILE
LOCATION '/user/${hivevar:hdfs_user}/convenience_retail/raw/products';

CREATE EXTERNAL TABLE stg_transactions (
    transaction_id BIGINT,
    transaction_date STRING,
    transaction_time STRING,
    customer_name STRING,
    customer_category STRING,
    city STRING,
    payment_method STRING,
    season STRING,
    promotion STRING,
    member STRING,
    total_items INT,
    total_cost DECIMAL(12,2)
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY '\001'
STORED AS TEXTFILE
LOCATION '/user/${hivevar:hdfs_user}/convenience_retail/raw/transactions';

CREATE EXTERNAL TABLE stg_transaction_items (
    transaction_id BIGINT,
    item_position INT,
    product_id INT
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\001'
STORED AS TEXTFILE
LOCATION '/user/${hivevar:hdfs_user}/convenience_retail/raw/transaction_items';

-- 2. Tạo các bảng Dimension chuẩn (không trùng khóa)
CREATE TABLE dim_product STORED AS ORC AS
SELECT DISTINCT product_id, product_name FROM stg_products;

CREATE TABLE dim_time STORED AS ORC AS
SELECT
    transaction_date AS date_str,
    year(transaction_date) AS trans_year,
    month(transaction_date) AS trans_month,
    quarter(transaction_date) AS trans_quarter
FROM stg_transactions
GROUP BY transaction_date;

CREATE TABLE dim_customer STORED AS ORC AS
SELECT
    ROW_NUMBER() OVER (ORDER BY customer_name, customer_category, member) AS customer_id,
    customer_name,
    customer_category,
    member
FROM (
    SELECT DISTINCT customer_name, customer_category, member
    FROM stg_transactions
) t;

CREATE TABLE dim_promotion STORED AS ORC AS
SELECT DISTINCT promotion FROM stg_transactions;

CREATE TABLE dim_payment STORED AS ORC AS
SELECT DISTINCT payment_method FROM stg_transactions;

-- 3. Tạo các bảng Fact gắn khóa ngoại chuẩn
CREATE TABLE fact_sales STORED AS ORC AS
SELECT
    t.transaction_id,
    t.transaction_date AS date_str,
    t.transaction_time,
    CASE
        WHEN hour(concat(t.transaction_date, ' ', t.transaction_time)) BETWEEN 5 AND 11 THEN 'Morning'
        WHEN hour(concat(t.transaction_date, ' ', t.transaction_time)) BETWEEN 12 AND 16 THEN 'Afternoon'
        WHEN hour(concat(t.transaction_date, ' ', t.transaction_time)) BETWEEN 17 AND 20 THEN 'Evening'
        ELSE 'Night'
    END AS time_of_day,
    c.customer_id,
    t.customer_name,
    t.city,
    t.payment_method,
    t.promotion,
    t.total_items,
    t.total_cost
FROM stg_transactions t
LEFT JOIN dim_customer c
  ON t.customer_name = c.customer_name
 AND t.customer_category = c.customer_category
 AND t.member = c.member;

CREATE TABLE fact_transaction_items STORED AS ORC AS
SELECT
    ti.transaction_id,
    ti.item_position,
    ti.product_id,
    p.product_name
FROM stg_transaction_items ti
LEFT JOIN dim_product p ON ti.product_id = p.product_id;
