
#!/bin/bash
set -euo pipefail

DB="jdbc:mysql://127.0.0.1:3306/convenience_retail"
HDFS="/user/$(whoami)/convenience_retail/raw"

# The text field order must match sql/01_hive_from_sqoop.sql exactly.
declare -A COLUMNS=(
    [products]='product_id,product_name'
    [transactions]='transaction_id,transaction_date,transaction_time,customer_name,customer_category,city,payment_method,season,promotion,member,total_items,total_cost'
    [transaction_items]='transaction_id,item_position,product_id'
)

for table in products transactions transaction_items
do
    echo "===== Import $table ====="

    sqoop import \
        --connect "$DB" \
        --username sqoopuser \
        -P \
        --table "$table" \
        --columns "${COLUMNS[$table]}" \
        --target-dir "$HDFS/$table" \
        --delete-target-dir \
        --as-textfile \
        --fields-terminated-by $'\001' \
        --num-mappers 1

    hdfs dfs -test -e "$HDFS/$table/_SUCCESS"
    count=$(hdfs dfs -cat "$HDFS/$table/part-m-*" | wc -l)

    echo "$table: $count dong"
done

echo "IMPORT HOAN THANH!"
