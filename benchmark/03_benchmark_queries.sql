-- Representative benchmark queries. The runner substitutes each of the four
-- table names. Q_C adds a month_str predicate only for partitioned tables,
-- while retaining the identical date filter.
-- These examples use the unpartitioned TextFile table.
USE retail_dw;

-- Q_A: Full scan, transaction count and revenue.
SELECT COUNT(*), SUM(total_cost)
FROM fact_sales_text_nopan;

-- Q_B: Aggregate revenue by month.
SELECT SUBSTR(date_str, 1, 7) AS month_str, SUM(total_cost)
FROM fact_sales_text_nopan
GROUP BY SUBSTR(date_str, 1, 7);

-- Q_C: Selective six-month range. For partitioned tables add
-- AND month_str BETWEEN '2022-01' AND '2022-06'.
SELECT COUNT(*), SUM(total_cost)
FROM fact_sales_text_nopan
WHERE date_str >= '2022-01-01' AND date_str < '2022-07-01';

-- Q_D: Group by payment method.
SELECT payment_method, SUM(total_cost)
FROM fact_sales_text_nopan
GROUP BY payment_method;
