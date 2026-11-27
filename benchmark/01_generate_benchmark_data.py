"""Optional local preflight for the Power BI export.

The benchmark itself reads Hive fact_sales, not this CSV. This script keeps
its historical name for compatibility but does not generate synthetic data.
"""

import csv
from decimal import Decimal, InvalidOperation
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPORT = ROOT / "data" / "powerbi_export" / "fact_sales.csv"


def main():
    if not EXPORT.is_file():
        raise SystemExit(f"Missing export: {EXPORT}")
    with EXPORT.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        required = {"transaction_id", "total_cost"}
        if not required.issubset(reader.fieldnames or []):
            raise SystemExit(f"Missing required CSV columns: {sorted(required)}")
        count = 0
        revenue = Decimal("0")
        try:
            for row in reader:
                count += 1
                revenue += Decimal(row["total_cost"])
        except (InvalidOperation, KeyError) as exc:
            raise SystemExit(f"Invalid exported revenue: {exc}") from exc
    if count != 18531 or abs(revenue - Decimal("936803.43")) > Decimal("0.01"):
        raise SystemExit(f"Export differs from baseline: rows={count}, revenue={revenue}")
    print(f"Power BI export matches source baseline: rows={count}, revenue={revenue}")
    print("Benchmark data is prepared from Hive fact_sales by 02_create_tables.sql")


if __name__ == "__main__":
    main()
