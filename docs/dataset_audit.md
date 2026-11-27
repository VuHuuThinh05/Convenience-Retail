# Kiểm tra bộ dữ liệu Kaggle: Convenience Store

- Nguồn: https://www.kaggle.com/datasets/jessekeats/convenience-store
- Dữ liệu nguồn có thể tải vào `data/raw/kaggle_convenience_store/`; bản sao `data/convenience_store.csv` có sẵn trong repo để xử lý offline.
- Giới hạn đọc mỗi file dữ liệu: 50,000 dòng (nếu đạt giới hạn thì không phải tổng số dòng).

## Danh sách file

- `data/convenience_store.csv` — bản sao dùng để xử lý offline.
- Khi tải lại từ Kaggle, `data/raw/kaggle_convenience_store/convenience_store.csv` là bản nguồn tải về.

## Cấu trúc dữ liệu

### convenience_store.csv
- Số dòng: **18,531** (đầy đủ).
- Số cột: **13**.
- Các cột: `Transaction_ID`, `Date`, `Customer_Name`, `Product`, `Total_Items`, `Total_Cost`, `Payment_Method`, `City`, `time_of_day`, `Customer_Category`, `Season`, `Promotion`, `Member`
- Mã giao dịch: `Transaction_ID`
- Sản phẩm: `Product`, `Total_Items`
- Đơn giá / doanh thu: `Total_Items`, `Total_Cost`
- Ngày giờ: `Date`, `time_of_day`
- Khách hàng: `Customer_Name`, `Customer_Category`, `Member`
- Mỗi mã giao dịch xuất hiện trong một dòng CSV; cột `Product` chứa **danh sách nhiều sản phẩm**. Cần tách danh sách để phân tích giỏ hàng. `Total_Items` là số phần tử trong danh sách, không phải số lượng riêng từng loại sản phẩm.
- Nhãn `Season` không nhất quán ngay trong cùng một ngày: `2022-06-20` có cả `Fall`, `Spring`, `Summer`, `Winter`. Trong 1.460 ngày, 1.241 ngày có đủ bốn nhãn. Vì vậy Q7 theo mùa đã được loại khỏi phân tích.
- Một số bản ghi đầu:
```json
{"Transaction_ID": "1000000000", "Date": "2022-06-20", "Customer_Name": "Michael Young", "Product": "['Tea', 'Swim Cap', 'Sandals', 'Slippers']", "Total_Items": "4", "Total_Cost": "38.27", "Payment_Method": "Cash", "City": "Eduardoberg", "time_of_day": "13:24:15", "Customer_Category": "Adult (30-49)", "Season": "Winter", "Promotion": "Discount on Selected Items", "Member": "No"}
{"Transaction_ID": "1000000001", "Date": "2023-07-23", "Customer_Name": "Lindsay Simmons", "Product": "['Band-Aids', 'Lighter Fluid', 'Beef']", "Total_Items": "3", "Total_Cost": "21.630000000000003", "Payment_Method": "Cash", "City": "Mariaton", "time_of_day": "09:56:29", "Customer_Category": "Young Adult (20-29)", "Season": "Winter", "Promotion": "Discount on Selected Items", "Member": "No"}
{"Transaction_ID": "1000000002", "Date": "2021-10-28", "Customer_Name": "Mrs. Jessica Reed", "Product": "['Onion Powder', 'Dish Soap', 'Salt', 'Aluminum Foil', 'Charcoal']", "Total_Items": "5", "Total_Cost": "43.190000000000005", "Payment_Method": "Mobile Payment", "City": "Strongview", "time_of_day": "18:29:29", "Customer_Category": "Adult (30-49)", "Season": "Summer", "Promotion": "BOGO (Buy One Get One)", "Member": "No"}
```

## Đối chiếu sơ bộ đề cương

- **Mã giao dịch:** `Transaction_ID`
- **Sản phẩm:** danh sách `Product`; `Total_Items` là kích thước giỏ
- **Số lượng riêng từng sản phẩm:** không có cột tương ứng
- **Tổng tiền giao dịch:** `Total_Cost`; không có đơn giá sản phẩm
- **Cửa hàng:** Chưa phát hiện cột tương ứng
- **Ngày giờ:** `Date`, `time_of_day`
- **Khách hàng:** `Customer_Category`, `Customer_Name`, `Member`

Các script `code/02_preprocess_data.py` và `code/03_validate_data.py` tách giỏ hàng, kiểm tra khóa và tổng tiền trước khi nạp MySQL. Không suy ra doanh thu sản phẩm hoặc hiệu quả cửa hàng từ những trường còn thiếu.
