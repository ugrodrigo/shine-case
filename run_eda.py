"""Run the DuckDB EDA and export the presentation-friendly result tables."""

from pathlib import Path

import duckdb


ROOT = Path(__file__).resolve().parent
DATABASE = ROOT / "shine_case.duckdb"
SQL_FILE = ROOT / "sql" / "shine_eda.sql"
KPI_SQL_FILE = ROOT / "sql" / "kpi_deep_dive.sql"
COHORT_SQL_FILE = ROOT / "sql" / "cohort_state_analysis.sql"
STREAK_SQL_FILE = ROOT / "sql" / "streak_analysis.sql"
CONCENTRATION_SQL_FILE = ROOT / "sql" / "revenue_concentration_analysis.sql"
PRESENTATION_SQL_FILE = ROOT / "sql" / "presentation_kpis.sql"
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
    "eda_post_activation_closures_monthly_by_segment",
    "eda_revenue_activity_transitions_by_segment",
    "eda_revenue_dropout_by_segment_type",
    "eda_sustained_revenue_inactivity_by_segment",
    "eda_two_month_revenue_inactivity_by_segment",
    "eda_revenue_return_probability_curve",
    "eda_company_revenue_lifecycle_state",
    "eda_revenue_lifecycle_state_by_segment",
    "eda_revenue_lifecycle_state_by_segment_type",
    "eda_revenue_trends_by_segment_type",
    "eda_ltv_proxy_by_cohort_age_segment_type",
    "eda_segment_scorecard",
    "eda_company_cohort_month_state",
    "eda_cohort_state_distribution_by_segment",
    "eda_cohort_state_matrix_by_segment",
    "eda_cohort_state_transitions_by_segment",
    "eda_company_revenue_streaks",
    "eda_cohort_streaks_by_segment",
    "eda_streak_next_month_persistence_by_segment",
    "eda_age3_streak_scorecard",
    "eda_company_cumulative_revenue_rank",
    "eda_top10_revenue_concentration_summary",
    "eda_top10_revenue_companies_by_segment",
    "eda_top10_revenue_by_type",
    "eda_top10_revenue_by_activation_cohort",
    "eda_company_age3_revenue_rank",
    "eda_age3_top10_revenue_summary",
    "eda_age3_top10_revenue_by_segment",
    "eda_revenue_concentration_curve",
    "eda_age3_revenue_concentration_curve",
    "eda_revenue_pareto_threshold",
    "eda_top20_revenue_concentration_summary",
    "eda_top20_revenue_companies_by_segment",
    "eda_top20_revenue_by_type",
    "eda_top20_revenue_by_activation_cohort",
    "eda_age3_top20_revenue_summary",
    "eda_age3_top20_revenue_by_segment",
    "eda_company_account_health_at_cutoff",
    "eda_account_health_by_segment",
    "eda_top20_account_health_summary",
]


def main() -> None:
    OUTPUT_DIR.mkdir(exist_ok=True)

    connection = duckdb.connect(str(DATABASE))
    try:
        connection.execute(SQL_FILE.read_text(encoding="utf-8"))
        connection.execute(KPI_SQL_FILE.read_text(encoding="utf-8"))
        connection.execute(COHORT_SQL_FILE.read_text(encoding="utf-8"))
        connection.execute(STREAK_SQL_FILE.read_text(encoding="utf-8"))
        connection.execute(CONCENTRATION_SQL_FILE.read_text(encoding="utf-8"))
        connection.execute(PRESENTATION_SQL_FILE.read_text(encoding="utf-8"))

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

        print("\nMonthly revenue-company activity transitions")
        transitions = connection.sql(
            """
            SELECT
                month_start,
                prior_revenue_companies,
                revenue_company_dropouts,
                reactivated_revenue_companies,
                one_month_revenue_company_dropout_pct
            FROM eda_revenue_activity_transitions_by_segment
            WHERE segment_level = 'overall'
            ORDER BY month_start
            """
        ).fetchdf()
        print(transitions.to_string(index=False))

        print("\nReturn probability after inactivity")
        return_curve = connection.sql(
            """
            SELECT
                inactive_months,
                spells_with_2_month_followup,
                return_within_next_2_months_pct
            FROM eda_revenue_return_probability_curve
            WHERE segment_level = 'overall'
            ORDER BY inactive_months
            """
        ).fetchdf()
        print(return_curve.to_string(index=False))

        print("\nRevenue lifecycle states at the April cutoff")
        states = connection.sql(
            """
            SELECT
                revenue_lifecycle_state,
                companies,
                segment_company_share_pct
            FROM eda_revenue_lifecycle_state_by_segment
            WHERE segment_level = 'overall'
            ORDER BY CASE revenue_lifecycle_state
                WHEN 'Active' THEN 1
                WHEN 'At-risk' THEN 2
                ELSE 3
            END
            """
        ).fetchdf()
        print(states.to_string(index=False))

        print(f"\nDatabase: {DATABASE}")
        print(f"CSV outputs: {OUTPUT_DIR}")
    finally:
        connection.close()


if __name__ == "__main__":
    main()
