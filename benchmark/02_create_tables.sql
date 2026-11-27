-- Run after sql/01_hive_from_sqoop.sql. The four tables use the same
-- transaction grain, columns, types and source rows. Only format and
-- monthly partitioning differ.
USE retail_dw;

DROP TABLE IF EXISTS fact_sales_text_nopan;
CREATE TABLE fact_sales_text_nopan (
    transaction_id BIGINT,
    date_str STRING,
    customer_name STRING,
    payment_method STRING,
    promotion STRING,
    total_items INT,
    total_cost DECIMAL(12,2)
) STORED AS TEXTFILE;
INSERT OVERWRITE TABLE fact_sales_text_nopan
SELECT transaction_id, date_str, customer_name, payment_method, promotion,
       total_items, CAST(total_cost AS DECIMAL(12,2))
FROM fact_sales;

DROP TABLE IF EXISTS fact_sales_orc_nopan;
CREATE TABLE fact_sales_orc_nopan (
    transaction_id BIGINT,
    date_str STRING,
    customer_name STRING,
    payment_method STRING,
    promotion STRING,
    total_items INT,
    total_cost DECIMAL(12,2)
) STORED AS ORC;
INSERT OVERWRITE TABLE fact_sales_orc_nopan
SELECT transaction_id, date_str, customer_name, payment_method, promotion,
       total_items, CAST(total_cost AS DECIMAL(12,2))
FROM fact_sales;

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;

DROP TABLE IF EXISTS fact_sales_text_pan;
CREATE TABLE fact_sales_text_pan (
    transaction_id BIGINT,
    date_str STRING,
    customer_name STRING,
    payment_method STRING,
    promotion STRING,
    total_items INT,
    total_cost DECIMAL(12,2)
) PARTITIONED BY (month_str STRING) STORED AS TEXTFILE;
INSERT OVERWRITE TABLE fact_sales_text_pan PARTITION (month_str)
SELECT transaction_id, date_str, customer_name, payment_method, promotion,
       total_items, CAST(total_cost AS DECIMAL(12,2)), SUBSTR(date_str, 1, 7)
FROM fact_sales;

DROP TABLE IF EXISTS fact_sales_orc_pan;
CREATE TABLE fact_sales_orc_pan (
    transaction_id BIGINT,
    date_str STRING,
    customer_name STRING,
    payment_method STRING,
    promotion STRING,
    total_items INT,
    total_cost DECIMAL(12,2)
) PARTITIONED BY (month_str STRING) STORED AS ORC;
INSERT OVERWRITE TABLE fact_sales_orc_pan PARTITION (month_str)
SELECT transaction_id, date_str, customer_name, payment_method, promotion,
       total_items, CAST(total_cost AS DECIMAL(12,2)), SUBSTR(date_str, 1, 7)
FROM fact_sales;
