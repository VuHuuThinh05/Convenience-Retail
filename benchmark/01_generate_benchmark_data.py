from pathlib import Path
import csv

def verify_and_prep_data():
    print("=== [01] KIEM TRA DU LIEU GOC CHO BENCHMARK ===")
    raw_file = Path("data/powerbi_export/fact_sales.csv")
    
    if not raw_file.exists():
        print(f"LỖI: Không tìm thấy file nguồn tại {raw_file}")
        return False
        
    row_count = 0
    with raw_file.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            row_count += 1
            
    print(f"OK: Đã tìm thấy fact_sales.csv với {row_count} dòng dữ liệu.")
    return True

if __name__ == "__main__":
    verify_and_prep_data()
