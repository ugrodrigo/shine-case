"""Run the DuckDB EDA and export the presentation-friendly result tables."""

from pathlib import Path

import duckdb


ROOT = Path(__file__).resolve().parent
DATABASE = ROOT / "shine_case.duckdb"
SQL_FILE = ROOT / "sql" / "shine_eda.sql"
KPI_SQL_FILE = ROOT / "sql" / "kpi_deep_dive.sql"
OUTPUT_DIR = ROOT / "eda_outputs"

OUTPUT_TABLES = [
    "eda_data_quality",
    "eda_may_coverage_check",
    "eda_funnel_by_signup_month",
    "eda_monthly_revenue",
    "eda_monthly_revenue_long",
    "eda_april_revenue_by_persona",
    "eda_april_revenue_by_initial_plan",
    "eda_activation_cohorts",
    "eda_missing_revenue_summary",
    "eda_missing_revenue_months",
    "eda_top_companies",
    "eda_component_concentration",
    "eda_negative_banking_fees",
    "eda_new_companies_by_month_segment",
    "eda_funnel_30d_by_signup_month_segment",
    "eda_churn_monthly_by_segment",
    "eda_revenue_trends_by_segment_type",
    "eda_ltv_proxy_by_cohort_age_segment_type",
    "eda_segment_scorecard",
]


def main() -> None:
    OUTPUT_DIR.mkdir(exist_ok=True)

    connection = duckdb.connect(str(DATABASE))
    try:
        connection.execute(SQL_FILE.read_text(encoding="utf-8"))
        connection.execute(KPI_SQL_FILE.read_text(encoding="utf-8"))

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
                analysis_status,
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

        print("\nThirty-day funnel (comparable signup cohorts)")
        funnel = connection.sql(
            """
            SELECT
                signup_month,
                eligible_signups,
                total_signup_to_activation_dropout_pct,
                pre_activation_closure_rate_pct
            FROM eda_funnel_30d_by_signup_month_segment
            WHERE segment_level = 'overall'
            ORDER BY signup_month
            """
        ).fetchdf()
        print(funnel.to_string(index=False))

        print("\nMonthly activated-company churn")
        churn = connection.sql(
            """
            SELECT
                month_start,
                active_at_start,
                churned_during_month,
                monthly_logo_churn_rate_pct
            FROM eda_churn_monthly_by_segment
            WHERE segment_level = 'overall'
            ORDER BY month_start
            """
        ).fetchdf()
        print(churn.to_string(index=False))

        print(f"\nDatabase: {DATABASE}")
        print(f"CSV outputs: {OUTPUT_DIR}")
    finally:
        connection.close()


if __name__ == "__main__":
    main()
