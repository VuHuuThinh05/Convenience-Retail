# Mô hình phân tích Hive

## Nguồn và grain

Nguồn là ba bảng MySQL `transactions`, `products`, `transaction_items`, được Sqoop chuyển lên HDFS rồi đọc qua các bảng external `stg_transactions`, `stg_products`, `stg_transaction_items` trong `sql/01_hive_from_sqoop.sql`. Dữ liệu gốc gồm 18.531 giao dịch, 311 sản phẩm và 89.564 dòng chi tiết giỏ hàng (2020-01-01 đến 2023-12-30).

| Bảng Hive | Grain | Khóa / liên kết dùng khi phân tích |
|---|---|---|
| `dim_time` | Một ngày | `date_str` duy nhất; năm, quý, tháng suy ra từ ngày |
| `dim_customer` | Một bộ `customer_name`, `customer_category`, `member` | `customer_id` sinh trong ETL; chỉ là khóa kỹ thuật của bộ dữ liệu, không phải ID khách hàng ngoài đời |
| `dim_product` | Một sản phẩm | `product_id` |
| `dim_payment` | Một phương thức thanh toán | `payment_method` |
| `dim_promotion` | Một loại khuyến mãi | `promotion` |
| `fact_sales` | Một giao dịch | `transaction_id`; liên kết `date_str` tới `dim_time` và `customer_id` tới `dim_customer` |
| `fact_transaction_items` | Một vị trí sản phẩm trong một giao dịch | `(transaction_id, item_position)`; liên kết `product_id` tới `dim_product` |

`fact_sales` còn lưu `city`, `payment_method`, `promotion`, `transaction_time`, `time_of_day`, `total_items`, `total_cost` để phục vụ các nhóm phân tích. `fact_transaction_items` dùng cho tần suất mua và các cặp sản phẩm. Không nhân `total_cost` qua từng dòng sản phẩm: số tiền này thuộc cả giao dịch.

Các truy vấn doanh số phải kiểm tra tổng `SUM(fact_sales.total_cost)` bằng **936803.43** trên phiên bản nguồn đã dùng. Kết quả giỏ hàng được tính bằng số giao dịch chứa sản phẩm/cặp sản phẩm; support, confidence và lift dùng số giao dịch làm mẫu số.

## Giới hạn diễn giải

- `City` là địa danh trong dữ liệu, không phải mã cửa hàng. Không đưa ra kết luận hiệu quả từng chi nhánh.
- `Customer_Name` có thể trùng giữa người khác nhau; `customer_id` trong Hive không chứng minh đây là khách hàng duy nhất qua thời gian.
- Không có giá, số lượng mua riêng từng loại sản phẩm; chỉ có danh sách các vị trí trong giỏ và tổng tiền giao dịch. Không tính doanh thu theo sản phẩm.
- Trường `Season` của nguồn không nhất quán với ngày giao dịch. Q7 theo mùa đã loại khỏi SQL phân tích và Power BI; trường này không thuộc `dim_time` dùng để báo cáo.
- So sánh TextFile/ORC và partitioning dùng cùng dữ liệu fact, tách kết quả đo khỏi kết quả phân tích kinh doanh. Bộ dữ liệu 18.531 giao dịch nhỏ đối với Hadoop, nên báo cáo rõ chi phí khởi động và điều kiện máy.

## Thứ tự kiểm chứng

1. Đối chiếu số dòng và một số bản ghi theo khóa giữa MySQL, HDFS và Hive staging.
2. Kiểm tra `fact_sales` có 18.531 `transaction_id` duy nhất; `fact_transaction_items` có 89.564 khóa `(transaction_id, item_position)` duy nhất và không có khóa mồ côi.
3. Đối chiếu tổng tiền nguồn → fact → các CSV tổng hợp; kiểm tra đường dẫn Power BI và làm mới dashboard.
4. Kiểm tra bốn bảng benchmark cùng số dòng và tổng tiền trước khi so sánh thời gian.
