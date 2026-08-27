"""Run the DuckDB EDA and export the presentation-friendly result tables."""

from pathlib import Path

import duckdb


ROOT = Path(__file__).resolve().parent
DATABASE = ROOT / "shine_case.duckdb"
SQL_FILE = ROOT / "sql" / "shine_eda.sql"
OUTPUT_DIR = ROOT / "eda_outputs"

OUTPUT_TABLES = [
    "eda_data_quality",
    "eda_funnel_by_signup_month",
    "eda_monthly_revenue",
    "eda_monthly_revenue_long",
    "eda_may_revenue_by_persona",
    "eda_may_revenue_by_initial_plan",
    "eda_activation_cohorts",
    "eda_missing_revenue_summary",
    "eda_missing_revenue_months",
    "eda_top_companies",
    "eda_component_concentration",
    "eda_negative_banking_fees",
]


def main() -> None:
    OUTPUT_DIR.mkdir(exist_ok=True)

    connection = duckdb.connect(str(DATABASE))
    try:
        connection.execute(SQL_FILE.read_text(encoding="utf-8"))

        for table in OUTPUT_TABLES:
            output_path = OUTPUT_DIR / f"{table}.csv"
            connection.sql(f"SELECT * FROM {table}").write_csv(str(output_path))
            row_count = connection.execute(
                f"SELECT COUNT(*) FROM {table}"
            ).fetchone()[0]
            print(f"Exported {table}: {row_count:,} rows")

        print("\nMonthly revenue")
        monthly = connection.sql(
            """
            SELECT
                revenue_month,
                revenue_companies,
                total_revenue,
                revenue_per_revenue_company,
                total_revenue_mom_growth_pct
            FROM eda_monthly_revenue
            ORDER BY revenue_month
            """
        ).fetchdf()
        print(monthly.to_string(index=False))

        print("\nMissing revenue-month diagnostic")
        missing = connection.sql(
            "SELECT * FROM eda_missing_revenue_summary"
        ).fetchdf()
        print(missing.to_string(index=False))

        print(f"\nDatabase: {DATABASE}")
        print(f"CSV outputs: {OUTPUT_DIR}")
    finally:
        connection.close()


if __name__ == "__main__":
    main()
