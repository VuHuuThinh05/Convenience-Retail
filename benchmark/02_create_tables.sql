USE retail_dw;

-- B1: TextFile, Không Partition
DROP TABLE IF EXISTS fact_sales_text_nopan;
CREATE TABLE fact_sales_text_nopan (
    transaction_id STRING,
    date_str STRING,
    customer_name STRING,
    payment_method STRING,
    promotion STRING,
    total_items INT,
    total_cost DECIMAL(10,2)
) STORED AS TEXTFILE;

INSERT OVERWRITE TABLE fact_sales_text_nopan 
SELECT transaction_id, date_str, customer_name, payment_method, promotion, total_items, total_cost FROM fact_sales;

-- B2: ORC, Không Partition
DROP TABLE IF EXISTS fact_sales_orc_nopan;
CREATE TABLE fact_sales_orc_nopan (
    transaction_id STRING,
    date_str STRING,
    customer_name STRING,
    payment_method STRING,
    promotion STRING,
    total_items INT,
    total_cost DECIMAL(10,2)
) STORED AS ORC;

INSERT OVERWRITE TABLE fact_sales_orc_nopan 
SELECT transaction_id, date_str, customer_name, payment_method, promotion, total_items, total_cost FROM fact_sales;

-- B3: TextFile, Có Partition theo tháng
DROP TABLE IF EXISTS fact_sales_text_pan;
CREATE TABLE fact_sales_text_pan (
    transaction_id STRING,
    date_str STRING,
    customer_name STRING,
    payment_method STRING,
    promotion STRING,
    total_items INT,
    total_cost DECIMAL(10,2)
) PARTITIONED BY (month_str STRING)
STORED AS TEXTFILE;

SET hive.exec.dynamic.partition.mode=nonstrict;
INSERT OVERWRITE TABLE fact_sales_text_pan PARTITION (month_str) 
SELECT transaction_id, date_str, customer_name, payment_method, promotion, total_items, total_cost, SUBSTR(date_str, 1, 7) AS month_str FROM fact_sales;

-- B4: ORC, Có Partition theo tháng
DROP TABLE IF EXISTS fact_sales_orc_pan;
CREATE TABLE fact_sales_orc_pan (
    transaction_id STRING,
    date_str STRING,
    customer_name STRING,
    payment_method STRING,
    promotion STRING,
    total_items INT,
    total_cost DECIMAL(10,2)
) PARTITIONED BY (month_str STRING)
STORED AS ORC;

INSERT OVERWRITE TABLE fact_sales_orc_pan PARTITION (month_str) 
SELECT transaction_id, date_str, customer_name, payment_method, promotion, total_items, total_cost, SUBSTR(date_str, 1, 7) AS month_str FROM fact_sales;
