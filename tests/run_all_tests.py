#!/usr/bin/env python3
"""Convenience Retail: 10 non-destructive checks for pipeline, BI exports and benchmarks.

Run from project root: python3 tests/run_all_tests.py
Service tests require available local CLI tools; unavailable tools get SKIP, never PASS.
No SQL modifies data. No credentials are embedded in this script.
"""
import argparse
import csv
from collections import Counter
from datetime import datetime
from decimal import Decimal, InvalidOperation
import getpass
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import time
import uuid

BASE = Path(__file__).resolve().parents[1]
EXPORTS = [
    "fact_sales.csv", "dim_customer.csv", "dim_product.csv", "dim_time.csv",
    "fact_transaction_items.csv", "q1_revenue_by_time.csv",
    "q2_revenue_by_payment.csv", "q3_revenue_by_city_time.csv",
    "q4_revenue_by_customer_category.csv", "q5_revenue_by_member.csv",
    "q6_revenue_by_promotion.csv",
    "q8_top_products.csv", "q9_market_basket_top20.csv",
]
EXPECTED_ROWS = {"transactions": 18531, "products": 311, "transaction_items": 89564}
BASELINE_REVENUE = Decimal("936803.43")

class SkipTest(Exception):
    pass

def require(condition, message):
    if not condition:
        raise AssertionError(message)

def data_file(root, name):
    return root / "data" / "powerbi_export" / name

def csv_rows(path, required=()):
    if not path.is_file():
        raise AssertionError(f"Thiếu file: {path}")
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        cols = reader.fieldnames or []
        missing = set(required) - set(cols)
        require(not missing, f"{path.name}: thiếu cột {sorted(missing)}")
        data = list(reader)
    require(bool(data), f"{path.name}: file rỗng")
    return data

def count_distinct(rows, col):
    return len({r[col] for r in rows})

def decimal_sum(rows, col):
    try:
        return sum((Decimal(r[col].strip()) for r in rows), Decimal("0"))
    except (InvalidOperation, KeyError) as exc:
        raise AssertionError(f"Dữ liệu số ở cột {col} không hợp lệ: {exc}") from exc

def cmd_exists(cmd):
    if not shutil.which(cmd):
        raise SkipTest(f"Không tìm thấy lệnh '{cmd}' trên hệ điều hành đang chạy. Hãy chạy trong WSL nếu dịch vụ ở WSL.")

def execute(args, timeout=90, stdin=None, cwd=None):
    try:
        process = subprocess.run(args, input=stdin, capture_output=True, text=True, cwd=cwd,
                                 encoding="utf-8", errors="replace", timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"Lệnh quá thời gian {timeout}s: {args[0]}") from exc
    except OSError as exc:
        raise AssertionError(f"Không chạy được {args[0]}: {exc}") from exc
    if process.returncode != 0:
        # Avoid echoing full command or potentially sensitive arguments.
        err = (process.stderr or process.stdout).strip()[-280:]
        raise AssertionError(f"Lệnh {args[0]} thất bại (exit {process.returncode}): {err}")
    return process.stdout

def number_from_output(output, cmd):
    for line in reversed(output.splitlines()):
        line = line.strip()
        if line.isdigit():
            return int(line)
    raise AssertionError(f"{cmd}: không đọc được số nguyên từ kết quả")

def mysql_count(table):
    cmd = os.environ.get("RETAIL_MYSQL_CMD", "mysql --batch --skip-column-names --database=convenience_retail")
    args = shlex.split(cmd)
    require(args, "RETAIL_MYSQL_CMD bị rỗng")
    cmd_exists(args[0])
    output = execute(args + ["-e", f"SELECT COUNT(*) FROM {table};"], timeout=30)
    return number_from_output(output, "mysql")

def hdfs_count(table):
    cmd_exists("hdfs")
    user = os.environ.get("RETAIL_HDFS_USER", getpass.getuser())
    path = f"/user/{user}/convenience_retail/raw/{table}/part-m-*"
    output = execute(["hdfs", "dfs", "-cat", path], timeout=90)
    return len(output.splitlines())

def hive_count(table):
    cmd_exists("hive")
    database = os.environ.get("RETAIL_HIVE_DB", "retail_dw")
    require(database.replace("_", "").isalnum(), "Tên RETAIL_HIVE_DB không hợp lệ")
    output = execute(["hive", "-S", "-e", f"USE {database}; SELECT COUNT(*) FROM {table};"], timeout=180, cwd=Path.home())
    return number_from_output(output, "hive")

def hive_revenue(table):
    cmd_exists("hive")
    database = os.environ.get("RETAIL_HIVE_DB", "retail_dw")
    require(database.replace("_", "").isalnum(), "Tên RETAIL_HIVE_DB không hợp lệ")
    output = execute(["hive", "-S", "-e", f"USE {database}; SELECT CAST(SUM(total_cost) AS DECIMAL(14,2)) FROM {table};"], timeout=180, cwd=Path.home())
    try:
        return Decimal(output.strip().splitlines()[-1])
    except (InvalidOperation, IndexError) as exc:
        raise AssertionError(f"Hive {table}: không đọc được tổng tiền") from exc

# T01–T10. Return (expected, actual, note). Exceptions -> FAIL or SKIP.
def t01_mysql(root):
    actual = {t: mysql_count(t) for t in EXPECTED_ROWS}
    require(actual == EXPECTED_ROWS, f"Số dòng MySQL không khớp mốc dữ liệu: {actual}")
    return str(EXPECTED_ROWS), str(actual), "MySQL kết nối được; ba bảng có số dòng đúng"

def t02_hdfs(root):
    cmd_exists("hdfs")
    user = os.environ.get("RETAIL_HDFS_USER", getpass.getuser())
    path = f"/user/{user}/convenience_retail/raw"
    execute(["hdfs", "dfs", "-test", "-d", path], timeout=30)
    return f"Thư mục {path} tồn tại", "Tồn tại", "HDFS truy cập được (không thay đổi dữ liệu)"

def t03_mysql_hdfs(root):
    pairs = {t: {"mysql": mysql_count(t), "hdfs": hdfs_count(t)} for t in EXPECTED_ROWS}
    bad = {k: v for k, v in pairs.items() if v["mysql"] != v["hdfs"]}
    require(not bad, f"Số dòng MySQL-HDFS không khớp: {bad}")
    return "Số dòng 3 bảng tương đương", str(pairs), "Đối chiếu số dòng; chưa phải kiểm tra toàn bộ nội dung bản ghi"

def t04_hive(root):
    names = ["stg_products", "stg_transactions", "stg_transaction_items",
             "fact_sales", "fact_transaction_items"]
    values = {t: hive_count(t) for t in names}
    expected = {"stg_products": 311, "stg_transactions": 18531,
                "stg_transaction_items": 89564, "fact_sales": 18531,
                "fact_transaction_items": 89564}
    require(values == expected, f"Số dòng Hive không khớp: {values}")
    stage_revenue = hive_revenue("stg_transactions")
    fact_revenue = hive_revenue("fact_sales")
    require(stage_revenue == fact_revenue == BASELINE_REVENUE,
            f"Tổng tiền Hive sai: staging={stage_revenue}, fact={fact_revenue}")
    return f"Hive staging/fact đúng số dòng và tổng tiền {BASELINE_REVENUE}", \
           f"{values}; staging={stage_revenue}, fact={fact_revenue}", \
           "Đối chiếu staging và fact Hive; không biến đổi dữ liệu"

def t05_unique_transaction(root):
    rows = csv_rows(data_file(root, "fact_sales.csv"), ("transaction_id",))
    ids = [r["transaction_id"] for r in rows]
    require(all(ids), "Có transaction_id rỗng")
    dup = len(ids) - len(set(ids))
    require(dup == 0, f"Có {dup} mã giao dịch trùng")
    require(len(rows) == EXPECTED_ROWS["transactions"], f"Số giao dịch là {len(rows)}, mốc {EXPECTED_ROWS['transactions']}")
    return "18531 giao dịch; 0 trùng", f"{len(rows)} giao dịch; {dup} trùng", "Kiểm tra dữ liệu fact_sales xuất ra Power BI"

def t06_item_keys(root):
    items = csv_rows(data_file(root, "fact_transaction_items.csv"), ("transaction_id", "product_id", "item_position"))
    products = csv_rows(data_file(root, "dim_product.csv"), ("product_id",))
    sales = csv_rows(data_file(root, "fact_sales.csv"), ("transaction_id",))
    pids = {p["product_id"] for p in products}
    tids = {s["transaction_id"] for s in sales}
    orphan_pid = sum(r["product_id"] not in pids for r in items)
    orphan_tid = sum(r["transaction_id"] not in tids for r in items)
    keys = [(r["transaction_id"], r["item_position"]) for r in items]
    dup_item = len(keys) - len(set(keys))
    require(orphan_pid == 0 and orphan_tid == 0 and dup_item == 0,
            f"Khóa lỗi: product={orphan_pid}, transaction={orphan_tid}, item-key={dup_item}")
    require(len(items) == EXPECTED_ROWS["transaction_items"], f"Chi tiết giỏ hàng {len(items)} dòng")
    return "0 khóa mồ côi; 0 khóa chi tiết trùng; 89564 dòng", \
           f"{len(items)} dòng; mồ côi {orphan_pid+orphan_tid}; trùng {dup_item}", "Đối chiếu cả khóa sản phẩm và giao dịch"

def t07_revenue(root):
    fact = csv_rows(data_file(root, "fact_sales.csv"), ("total_cost",))
    value = decimal_sum(fact, "total_cost")
    source = root / "data" / "processed" / "transactions.csv"
    if source.is_file():
        source_value = decimal_sum(csv_rows(source, ("total_cost",)), "total_cost")
        require(abs(source_value - value) <= Decimal("0.01"), f"Revenue fact={value}, nguồn={source_value}")
    else:
        source_value = None
    require(abs(value - BASELINE_REVENUE) <= Decimal("0.01"), f"Revenue fact={value}, mốc={BASELINE_REVENUE}")
    note = "Đối chiếu dữ liệu nguồn và mốc Kaggle" if source_value is not None else "Chỉ đối chiếu mốc Kaggle; thiếu CSV processed để so sánh nguồn trực tiếp"
    return f"{BASELINE_REVENUE}", str(value), note

def t08_business_exports(root):
    names = [n for n in EXPORTS if n.startswith("q")]
    counts = {n[:-4]: len(csv_rows(data_file(root, n))) for n in names}
    q9 = csv_rows(data_file(root, "q9_market_basket_top20.csv"),
                  ("item_a", "item_b", "co_occurrence", "support", "confidence_a_to_b", "lift"))
    for i, r in enumerate(q9, 1):
        try:
            sup, conf, lift = float(r["support"]), float(r["confidence_a_to_b"]), float(r["lift"])
            co = int(r["co_occurrence"])
        except ValueError as exc:
            raise AssertionError(f"Q9 dòng {i}: chỉ số không phải số") from exc
        require(0 <= sup <= 1 and 0 <= conf <= 1 and lift > 0 and co > 0,
                f"Q9 dòng {i}: Support/Confidence/Lift/Frequency không hợp lệ")
    require(len(q9) <= 20, f"Q9 có {len(q9)} dòng, lớn hơn Top 20")
    return "8 file CSV Q1-Q6, Q8-Q9 không rỗng; Q9 hợp lệ", \
           ", ".join(f"{k}={v}" for k, v in counts.items()), \
           "Kiểm tra cấu trúc, miền chỉ số; không thay thế việc đối chiếu SQL Hive"

def t09_powerbi_exports(root):
    counts = {n: len(csv_rows(data_file(root, n))) for n in EXPORTS}
    fields = {
        "fact_sales.csv": ("transaction_id", "customer_id", "date_str", "total_items", "total_cost"),
        "dim_customer.csv": ("customer_id",),
        "dim_product.csv": ("product_id", "product_name"),
        "dim_time.csv": ("date_str", "trans_year", "trans_month"),
        "fact_transaction_items.csv": ("transaction_id", "product_id", "item_position"),
    }
    for name, cols in fields.items():
        csv_rows(data_file(root, name), cols)
    for name, key in (("dim_customer.csv", "customer_id"), ("dim_product.csv", "product_id"), ("dim_time.csv", "date_str")):
        rows = csv_rows(data_file(root, name), (key,))
        require(count_distinct(rows, key) == len(rows), f"{name}: khóa {key} không duy nhất")
    return "13 file CSV, khóa dim duy nhất", f"{len(counts)} file", "Kiểm tra cấu trúc xuất CSV và khóa dimension"

def t10_benchmark(root):
    path = root / "results" / "benchmark" / "benchmark_results.csv"
    rows = csv_rows(path, ("run_id", "query_id", "format", "partitioned", "run_number", "duration_ms", "status"))
    groups = Counter((r["format"], r["partitioned"], r["query_id"]) for r in rows)
    expected = {(fmt, part, q): 3 for fmt in ("TextFile", "ORC") for part in ("No", "Yes") for q in ("Q_A", "Q_B", "Q_C", "Q_D")}
    require(groups == expected, f"Benchmark thiếu/thừa nhóm: {groups}")
    require(len(rows) == 48, f"Số phép đo {len(rows)} không phải 48")
    require(all(r["status"] == "SUCCESS" and float(r["duration_ms"]) > 0 for r in rows),
            "Benchmark có status khác SUCCESS hoặc thời gian không dương")
    run_ids = {r["run_id"] for r in rows}
    require(len(run_ids) == 1, "Benchmark chứa nhiều run_id")
    validation = root / "results" / "benchmark" / "benchmark_validation.csv"
    audits = csv_rows(validation, ("run_id", "table_name", "row_count", "total_revenue",
                                   "range_row_count", "range_revenue", "hdfs_size_bytes"))
    require(len(audits) == 4 and {r["run_id"] for r in audits} == run_ids,
            "Thiếu xác thực bốn bảng cho lần benchmark hiện tại")
    require(len({r["table_name"] for r in audits}) == 4,
            "Bảng benchmark trùng hoặc thiếu")
    require(all(int(r["row_count"]) == EXPECTED_ROWS["transactions"]
                and Decimal(r["total_revenue"]) == BASELINE_REVENUE
                and int(r["range_row_count"]) > 0
                and int(r["hdfs_size_bytes"]) > 0 for r in audits),
            "Bảng benchmark sai số dòng, tổng tiền, khoảng lọc hoặc dung lượng")
    require(len({(r["range_row_count"], r["range_revenue"]) for r in audits}) == 1,
            "Bốn bảng benchmark khác kết quả khoảng lọc")
    summary = root / "results" / "benchmark" / "benchmark_summary.csv"
    if summary.exists():
        sums = csv_rows(summary, ("query_id", "format", "partitioned", "runs", "median_duration_ms"))
        require(len(sums) == 16 and all(int(x["runs"]) == 3 for x in sums),
                "benchmark_summary.csv không đủ 16 dòng hoặc số lần đo không đúng")
    return "48 SUCCESS, 16 nhóm × 3 phép đo; 4 bảng đã đối chiếu", f"{len(rows)} SUCCESS", \
           "Cùng số dòng, tổng tiền, kết quả khoảng lọc và có dung lượng HDFS"

TESTS = [
    ("T01", "MySQL - kết nối và số dòng", t01_mysql),
    ("T02", "HDFS - thư mục dữ liệu", t02_hdfs),
    ("T03", "MySQL so với HDFS", t03_mysql_hdfs),
    ("T04", "Hive - truy vấn fact", t04_hive),
    ("T05", "Giao dịch không trùng khóa", t05_unique_transaction),
    ("T06", "Khóa giỏ hàng và sản phẩm", t06_item_keys),
    ("T07", "Đối chiếu tổng doanh thu", t07_revenue),
    ("T08", "Kiểm tra kết quả Q1-Q6, Q8-Q9", t08_business_exports),
    ("T09", "Kiểm tra CSV Power BI", t09_powerbi_exports),
    ("T10", "Kiểm tra benchmark", t10_benchmark),
]

def append_csv(path, fieldnames, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    has_header = path.is_file() and path.stat().st_size > 0
    with path.open("a", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        if not has_header:
            w.writeheader()
        w.writerows(records)

def main():
    parser = argparse.ArgumentParser(description="Chạy bộ kiểm thử Convenience Retail T01–T10")
    parser.add_argument("--root", type=Path, default=BASE, help="Đường dẫn gốc của repository")
    args = parser.parse_args()
    root = args.root.resolve()
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    executed_at = datetime.now().astimezone().isoformat(timespec="seconds")
    records = []
    for tid, name, func in TESTS:
        started = time.monotonic()
        try:
            expected, actual, note = func(root)
            status, error = "PASS", ""
        except SkipTest as exc:
            expected, actual, note = "Kiểm tra được dịch vụ", "Không đủ điều kiện", "Không có công cụ/kết nối"
            status, error = "SKIP", str(exc)
        except Exception as exc:
            expected, actual, note = "Điều kiện kiểm thử đạt", "Chưa đạt", "Chi tiết trong error_message"
            status, error = "FAIL", f"{type(exc).__name__}: {exc}"
        elapsed = round((time.monotonic() - started) * 1000)
        records.append({
            "run_id": run_id, "test_id": tid, "test_name": name,
            "status": status, "duration_ms": elapsed, "executed_at": executed_at,
            "expected_value": expected, "actual_value": actual,
            "error_message": error, "note": note,
        })
        print(f"{tid}  {status:<4}  {name} ({elapsed} ms)" + (f" — {error[:150]}" if error else ""))
    output = root / "results" / "testing"
    append_csv(output / "test_results.csv", list(records[0]), records)
    counts = Counter(r["status"] for r in records)
    summary = {
        "run_id": run_id, "executed_at": executed_at, "total": len(records),
        "pass": counts["PASS"], "fail": counts["FAIL"], "skip": counts["SKIP"],
        "pass_rate_pct_all": round(100 * counts["PASS"] / len(records), 2),
        "duration_ms": sum(r["duration_ms"] for r in records),
    }
    append_csv(output / "test_summary.csv", list(summary), [summary])
    print(f"\nKẾT QUẢ: PASS={counts['PASS']} FAIL={counts['FAIL']} SKIP={counts['SKIP']} (tổng 10)")
    print(f"Đã ghi: {output / 'test_results.csv'} và {output / 'test_summary.csv'}")
    return 1 if counts["FAIL"] else 0

if __name__ == "__main__":
    raise SystemExit(main())
