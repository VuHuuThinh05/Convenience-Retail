#!/usr/bin/env bash
# Build the canonical Hive warehouse from the three Sqoop text imports.
set -euo pipefail

cd "$(dirname "$0")/.."
hdfs_user="${RETAIL_HDFS_USER:-$(whoami)}"
hdfs_root="/user/${hdfs_user}/convenience_retail/raw"

for spec in 'products 311' 'transactions 18531' 'transaction_items 89564'; do
    read -r table expected <<< "$spec"
    hdfs dfs -test -e "$hdfs_root/$table/_SUCCESS"
    actual=$(hdfs dfs -cat "$hdfs_root/$table/part-m-*" | wc -l)
    if [[ "$actual" -ne "$expected" ]]; then
        echo "HDFS $table: $actual rows; expected $expected" >&2
        exit 1
    fi
done

bash scripts/hive_cli.sh --hivevar "hdfs_user=$hdfs_user" -f sql/01_hive_from_sqoop.sql

actual=$(bash scripts/hive_cli.sh -S -e 'USE retail_dw; SELECT COUNT(*), CAST(SUM(total_cost) AS DECIMAL(14,2)) FROM fact_sales;' | tail -n 1)
if [[ "$actual" != $'18531\t936803.43' ]]; then
    echo "Hive fact_sales count/revenue mismatch: $actual" >&2
    exit 1
fi

actual=$(bash scripts/hive_cli.sh -S -e 'USE retail_dw; SELECT COUNT(*) FROM fact_transaction_items;' | tail -n 1)
if [[ "$actual" != '89564' ]]; then
    echo "Hive fact_transaction_items count mismatch: $actual" >&2
    exit 1
fi

echo 'Hive warehouse validated: 18531 transactions, 89564 items, revenue 936803.43'
