from pathlib import Path
import csv

def analyze_results():
    path = Path("results/benchmark/benchmark_results.csv")
    if not path.exists():
        print("Chưa có file kết quả benchmark.")
        return
        
    data = []
    with path.open(encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["status"] == "SUCCESS":
                row["duration_ms"] = float(row["duration_ms"])
                data.append(row)
                
    if not data:
        print("Không có dữ liệu thành công.")
        return

    print("=== TONG KET HIEU NANG BENCHMARK (TB THỜI GIAN MS) ===")
    print(f"{'Query':<6} | {'Format':<10} | {'Partition':<10} | {'Avg Duration (ms)':<18}")
    print("-" * 55)
    
    groups = {}
    for row in data:
        key = (row["query_id"], row["format"], row["partitioned"])
        groups.setdefault(key, []).append(row["duration_ms"])
        
    for (qid, fmt, part), times in sorted(groups.items()):
        avg_time = sum(times) / len(times)
        print(f"{qid:<6} | {fmt:<10} | {part:<10} | {avg_time:<18.2f}")

if __name__ == "__main__":
    analyze_results()
