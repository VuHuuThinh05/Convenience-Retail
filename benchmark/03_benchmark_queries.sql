SELECT COUNT(*), SUM(total_cost) FROM [TABLE_NAME];
SELECT SUBSTR(date_str, 1, 7) AS m, SUM(total_cost) FROM [TABLE_NAME] GROUP BY SUBSTR(date_str, 1, 7);
SELECT COUNT(*), SUM(total_cost) FROM [TABLE_NAME] WHERE date_str >= '2025-01-01' AND date_str <= '2025-06-30';
SELECT city, SUM(total_cost) FROM [TABLE_NAME] GROUP BY city;
