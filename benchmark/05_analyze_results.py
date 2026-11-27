"""Summarize one complete benchmark run without claiming universal speedups."""

import csv
from collections import defaultdict
from pathlib import Path
from statistics import mean, median

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / "results" / "benchmark"
RESULTS = DIR / "benchmark_results.csv"
VALIDATION = DIR / "benchmark_validation.csv"
SUMMARY = DIR / "benchmark_summary.csv"


def rows(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def main():
    if not RESULTS.is_file():
        raise SystemExit(f"Missing measurements: {RESULTS}")
    measured = rows(RESULTS)
    run_ids = {row["run_id"] for row in measured}
    if len(run_ids) != 1:
        raise SystemExit(f"Expected one run_id in measurements, found {sorted(run_ids)}")
    run_id = run_ids.pop()
    groups = defaultdict(list)
    for row in measured:
        if row["status"] != "SUCCESS":
            raise SystemExit(f"Measurement failed: {row}")
        groups[(row["query_id"], row["format"], row["partitioned"])].append(
            float(row["duration_ms"])
        )
    expected = {(q, fmt, part) for q in ("Q_A", "Q_B", "Q_C", "Q_D")
                for fmt in ("TextFile", "ORC") for part in ("No", "Yes")}
    if set(groups) != expected or any(len(times) != 3 for times in groups.values()):
        raise SystemExit("Incomplete benchmark: expected 16 groups of 3 runs")

    validated = False
    if VALIDATION.is_file():
        audit = rows(VALIDATION)
        validated = (len(audit) == 4 and {row["run_id"] for row in audit} == {run_id}
                     and len({(row["row_count"], row["total_revenue"],
                               row["range_row_count"], row["range_revenue"]) for row in audit}) == 1)
    if not validated:
        print("No matching four-table validation for this run; historical timing only.")

    fields = ["query_id", "format", "partitioned", "runs", "avg_duration_ms",
              "median_duration_ms", "min_duration_ms", "max_duration_ms"]
    with SUMMARY.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for (qid, fmt, part), times in sorted(groups.items()):
            writer.writerow({
                "query_id": qid, "format": fmt, "partitioned": part,
                "runs": len(times), "avg_duration_ms": round(mean(times), 2),
                "median_duration_ms": round(median(times), 2),
                "min_duration_ms": round(min(times), 2),
                "max_duration_ms": round(max(times), 2),
            })
            print(f"{qid} {fmt:8} partition={part:3} median={median(times):.0f} ms")
    if validated:
        print("Matched validation: all four tables have the same row counts and revenue.")
        for row in audit:
            print(f"  {row['table_name']}: {row['hdfs_size_bytes']} HDFS bytes")
    print("Timing includes Hive CLI startup; 18,531 transactions limit generalization.")
    print(f"Summary saved: {SUMMARY}")


if __name__ == "__main__":
    main()
