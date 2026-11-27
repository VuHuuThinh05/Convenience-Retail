# Convenience Retail Big Data — Hadoop Pipeline

Dự án phân tích giao dịch cửa hàng tiện lợi theo lô trên môi trường Hadoop pseudo-distributed. Phạm vi bám theo đề cương đã duyệt: MySQL → Sqoop → HDFS → Hive → Power BI, phân tích doanh số và giỏ hàng, đánh giá TextFile/ORC và partitioning.

## Dữ liệu và phạm vi kết luận

Nguồn: [Convenience Store — jessekeats (Kaggle)](https://www.kaggle.com/datasets/jessekeats/convenience-store). Bộ dữ liệu đã dùng có **18.531 giao dịch, 311 sản phẩm, 89.564 dòng sản phẩm trong giỏ** và tổng `total_cost` **936803.43** (chưa xác minh đơn vị tiền tệ). Mỗi dòng `fact_sales` là một giao dịch; `total_cost` chỉ được cộng một lần ở cấp giao dịch.

Nguồn không có StoreID, mã khách hàng bền vững hay giá bán riêng từng sản phẩm. `City` không đại diện cho cửa hàng; `Customer_Name` không phải khóa khách hàng đáng tin cậy. Phân tích giỏ hàng dùng tần suất đồng xuất hiện, support, confidence và lift; không gán doanh thu cho từng sản phẩm. **Q7 theo mùa đã loại khỏi SQL phân tích, CSV xuất và biểu đồ** vì nhãn `Season` trong dữ liệu nguồn không nhất quán với ngày. Trường nguồn vẫn được giữ để bảo toàn dữ liệu đầu vào, nhưng không dùng làm chỉ số kinh doanh. File Power BI đã lưu không còn bảng Q7 trong khung Data, nhưng vẫn còn trường `dim_time.season` và một nút Q7 cũ trong metadata sơ đồ mô hình; cần kiểm tra các dấu vết này khi làm mới báo cáo.

## Môi trường

Môi trường tham chiếu: Windows + WSL2 Ubuntu 22.04, Python 3.10, Java 8, Hadoop 3.2.1, Hive 3.1.2, Sqoop 1.4.7 và MySQL 8. Cần cài và cấu hình các dịch vụ này trên máy chạy; Git clone không tự thiết lập Hadoop, MySQL, Hive Metastore hoặc HDFS. Mọi lệnh bên dưới chạy tại thư mục gốc dự án trong terminal WSL.

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

## Chạy pipeline

1. **Lấy và kiểm tra dữ liệu.** Có thể dùng bản sao `data/convenience_store.csv` đang có trong repo để chạy offline, hoặc tải lại bằng `python code/00_download_dataset.py`. Chạy tiếp `python code/02_preprocess_data.py` và `python code/03_validate_data.py`. Script ưu tiên bản tải về `data/raw/kaggle_convenience_store/convenience_store.csv`, rồi dùng bản sao offline khi không có file đó; kết quả xử lý nằm ở `data/processed/`. Nếu Kaggle yêu cầu đăng nhập, dùng tài khoản cá nhân và không đưa token vào repo.
2. **Nạp MySQL.** Chạy `sudo service mysql start`, `sudo mysql < sql/mysql/create_tables.sql`, rồi `python code/04_load_mysql.py`. Bước nạp **xóa và nạp lại** ba bảng `transactions`, `products`, `transaction_items`; chỉ chạy trên database dành cho đồ án.
3. **Tạo tài khoản Sqoop chỉ đọc** trong MySQL, ví dụ `CREATE USER 'sqoopuser'@'127.0.0.1' IDENTIFIED BY 'MAT_KHAU_RIENG'; GRANT SELECT ON convenience_retail.* TO 'sqoopuser'@'127.0.0.1';`. Kiểm tra bằng `sqoop list-tables --connect jdbc:mysql://127.0.0.1:3306/convenience_retail --username sqoopuser -P`.
4. **Đưa dữ liệu lên HDFS.** Chạy `sudo service ssh start`, `start-dfs.sh`, `start-yarn.sh`, rồi `bash scripts/01_import_sqoop.sh`. Script nhập lại ba thư mục `/user/<tên-user>/convenience_retail/raw/` bằng `--delete-target-dir`; không chạy khi tác vụ khác đang đọc dữ liệu ở đó.
5. **Tạo mô hình Hive từ dữ liệu Sqoop.** Chạy `bash scripts/02_build_hive.sh`. Script truyền user HDFS vào `sql/01_hive_from_sqoop.sql` để đọc đúng ba thư mục đã nhập. Đây là luồng dựng mô hình Hive của dự án.
6. **Phân tích và xuất Power BI.** Chạy `bash scripts/hive_cli.sh -f sql/04_replay_analysis.sql`, sau đó `mkdir -p data/powerbi_export` và `bash scripts/export_powerbi.sh data/powerbi_export`. Mở `dashboard_biadata.pbix` trong Power BI và cập nhật đường dẫn nguồn CSV trên máy chạy. Các câu hỏi đang sử dụng: **Q1–Q6, Q8–Q9**; không có biểu đồ Q7.
7. **Kiểm thử.** Chạy `python tests/run_all_tests.py` sau khi MySQL, HDFS, Hive và dữ liệu xuất sẵn sàng. Kiểm tra tổng giao dịch, sản phẩm, chi tiết giỏ, tổng tiền và khóa trước khi dùng số liệu trong báo cáo. Log cũ trong `results/testing/` là lịch sử, không thay thế kết quả của lần chạy cuối.

Ngày 25/11/2026, mô hình Hive đã được dựng lại từ HDFS và đối chiếu thành công **18.531 giao dịch, 89.564 chi tiết giỏ, tổng tiền 936803.43**. Các CSV trong `data/powerbi_export/` đã được xuất lại từ mô hình này. Lần kiểm thử WSL gần nhất trong `results/testing/test_summary.csv` đạt **10/10 (100%)** sau khi cấu hình kết nối MySQL hợp lệ. Dashboard Power BI cần làm mới và lưu để phản ánh lần chạy này.

Để T01/T03 kết nối MySQL mà không ghi mật khẩu vào script, tạo login path bằng `mysql_config_editor set --login-path=retail_test --host=127.0.0.1 --user=sqoopuser --password` (nhập mật khẩu tại lời nhắc), thử `mysql --login-path=retail_test --database=convenience_retail -e 'SELECT COUNT(*) FROM transactions;'`, rồi đặt `export RETAIL_MYSQL_CMD='mysql --login-path=retail_test --batch --skip-column-names --database=convenience_retail'` trước khi chạy lại `python tests/run_all_tests.py`. Nếu user HDFS khác user đang chạy kiểm thử, đặt `RETAIL_HDFS_USER` tương ứng.

## Đánh giá hiệu năng

Sau khi `fact_sales` trong Hive có dữ liệu, tạo bốn bảng so sánh bằng `bash scripts/hive_cli.sh -f benchmark/02_create_tables.sql`, chạy `bash benchmark/04_run_benchmark.sh`, rồi `python benchmark/05_analyze_results.py`. Wrapper `scripts/hive_cli.sh` chạy Hive từ thư mục home của WSL để Hive Metastore/Derby không tạo file trong `/mnt/d`. So sánh **TextFile và ORC**, mỗi loại có và không partition theo tháng, trên cùng số dòng và tổng tiền. Lần chạy ngày 25/11/2026 có **48/48 phép đo thành công**; `results/benchmark/benchmark_validation.csv` ghi số dòng, tổng tiền, kết quả lọc và dung lượng HDFS của bốn bảng. Với 18.531 giao dịch, chi phí khởi động Hive có thể chi phối thời gian; chỉ kết luận theo các phép đo thực tế, không khẳng định một định dạng luôn nhanh hơn.

## Tài liệu

- `docs/data_mapping.md`: ánh xạ dữ liệu nguồn → MySQL → Hive và giới hạn diễn giải.
- `docs/star_schema_design.md`: grain và quan hệ các bảng phân tích.
- `docs/dataset_audit.md`: khảo sát và chất lượng dữ liệu gốc.

Tham khảo: [Apache Hadoop](https://hadoop.apache.org/docs/), [Apache Hive](https://hive.apache.org/), và Kimball & Ross, *The Data Warehouse Toolkit* (2013).
