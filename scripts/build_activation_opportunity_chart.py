from pathlib import Path

import duckdb
import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATABASE = PROJECT_ROOT / "data" / "shine_case.duckdb"
OUTPUT = (
    PROJECT_ROOT
    / "outputs"
    / "presentation"
    / "assets"
    / "simple_raw_activation_opportunity.png"
)

NAVY = "#102A43"
TEAL = "#2A9D8F"
BLUE = "#6AAED6"
MID_GREY = "#526574"
LIGHT_GREY = "#E6ECEF"


def load_metrics():
    connection = duckdb.connect(str(DATABASE), read_only=True)
    try:
        activation_curve = connection.execute(
            """
            WITH validation_cohort AS (
                SELECT
                    validation_date,
                    activation_date,
                    DATE_DIFF('day', validation_date, activation_date)
                        AS days_to_activation
                FROM companies
                WHERE validation_date BETWEEN DATE '2025-10-01'
                                          AND DATE '2026-01-30'
            )
            SELECT
                COUNT(*) AS validated_companies,
                100.0 * COUNT(*) FILTER (
                    WHERE days_to_activation BETWEEN 0 AND 7
                ) / COUNT(*) AS day_7,
                100.0 * COUNT(*) FILTER (
                    WHERE days_to_activation BETWEEN 0 AND 14
                ) / COUNT(*) AS day_14,
                100.0 * COUNT(*) FILTER (
                    WHERE days_to_activation BETWEEN 0 AND 30
                ) / COUNT(*) AS day_30,
                100.0 * COUNT(*) FILTER (
                    WHERE days_to_activation BETWEEN 0 AND 60
                ) / COUNT(*) AS day_60,
                100.0 * COUNT(*) FILTER (
                    WHERE days_to_activation BETWEEN 0 AND 90
                ) / COUNT(*) AS day_90
            FROM validation_cohort
            """
        ).fetchdf().iloc[0]

        opportunity = connection.execute(
            """
            WITH validated_volume AS (
                SELECT
                    persona,
                    COUNT(*) / 6.0 AS validated_companies_per_month
                FROM companies
                WHERE validation_date >= DATE '2025-10-01'
                  AND validation_date < DATE '2026-04-01'
                GROUP BY persona
            ),
            april_revenue AS (
                SELECT
                    c.persona,
                    SUM(r.total_revenue)
                        / COUNT(DISTINCT r.company_profile_id)
                        AS april_revenue_per_company
                FROM companies c
                JOIN revenue_with_total r USING (company_profile_id)
                WHERE r.revenue_month = DATE '2026-04-01'
                GROUP BY c.persona
            ),
            persona_scenarios AS (
                SELECT
                    v.persona,
                    v.validated_companies_per_month,
                    a.april_revenue_per_company,
                    v.validated_companies_per_month
                        * a.april_revenue_per_company AS weighted_revenue_base
                FROM validated_volume v
                JOIN april_revenue a USING (persona)
            )
            SELECT
                SUM(validated_companies_per_month)
                    AS validated_companies_per_month,
                SUM(weighted_revenue_base)
                    / SUM(validated_companies_per_month)
                    AS weighted_april_revenue_per_company
            FROM persona_scenarios
            """
        ).fetchdf().iloc[0]
    finally:
        connection.close()
    return activation_curve, opportunity


def build_chart():
    curve, opportunity = load_metrics()
    days = np.array([7, 14, 30, 60, 90])
    rates = np.array(
        [
            curve["day_7"],
            curve["day_14"],
            curve["day_30"],
            curve["day_60"],
            curve["day_90"],
        ],
        dtype=float,
    )
    validated_per_month = float(opportunity["validated_companies_per_month"])
    revenue_per_company = float(opportunity["weighted_april_revenue_per_company"])
    uplift_points = np.array([5.0, 10.0])
    extra_per_cohort = validated_per_month * uplift_points / 100.0
    mature_cohort_run_rate = extra_per_cohort * revenue_per_company
    three_mature_cohorts_run_rate = mature_cohort_run_rate * 3.0

    fig, axes = plt.subplots(
        1,
        2,
        figsize=(12.2, 5.25),
        dpi=190,
        gridspec_kw={"width_ratios": [1.25, 1.0]},
    )
    fig.patch.set_facecolor("white")

    left = axes[0]
    left.plot(days, rates, color=TEAL, linewidth=3.0, marker="o", markersize=6)
    left.fill_between(days, rates, color=TEAL, alpha=0.10)
    left.axvline(30, color="#D39A2C", linewidth=1.3, linestyle="--")
    for day, rate in zip(days, rates):
        left.text(
            day,
            rate + 3.0,
            f"{rate:.1f}%",
            ha="center",
            va="bottom",
            fontsize=9,
            fontweight="bold",
            color=NAVY,
        )
    left.annotate(
        f"+{rates[-1] - rates[2]:.1f} pp activate after day 30",
        xy=(60, rates[3]),
        xytext=(48, 88),
        arrowprops={"arrowstyle": "->", "color": MID_GREY, "lw": 1.1},
        fontsize=8.5,
        color=MID_GREY,
    )
    left.text(
        90,
        rates[-1] - 9,
        f"{100 - rates[-1]:.1f}% still not activated\nby day 90",
        ha="right",
        va="top",
        fontsize=8.5,
        color="#B4513A",
    )
    left.set_title(
        "Activation continues beyond the first month",
        loc="left",
        fontsize=12,
        fontweight="bold",
        color=NAVY,
    )
    left.set_xlabel("Days after KYB validation", fontsize=9.5, color=MID_GREY)
    left.set_ylabel("Cumulative share activated", fontsize=9.5, color=MID_GREY)
    left.set_xticks(days)
    left.set_ylim(0, 100)
    left.set_yticks([0, 25, 50, 75, 100], ["0%", "25%", "50%", "75%", "100%"])
    left.grid(axis="y", color=LIGHT_GREY, linewidth=0.8)
    left.set_axisbelow(True)

    right = axes[1]
    y = np.arange(len(uplift_points))
    bars = right.barh(y, mature_cohort_run_rate / 1000, color=[BLUE, TEAL], height=0.56)
    right.set_yticks(y, ["+5 pp", "+10 pp"], fontsize=10, color=NAVY)
    right.invert_yaxis()
    right.set_xlim(0, max(mature_cohort_run_rate / 1000) * 1.62)
    right.set_xlabel(
        "Additional monthly revenue per matured validation cohort",
        fontsize=9.2,
        color=MID_GREY,
    )
    right.set_title(
        "Illustrative 90-day conversion scenarios",
        loc="left",
        fontsize=12,
        fontweight="bold",
        color=NAVY,
    )
    for bar, run_rate, extra, three_cohorts in zip(
        bars, mature_cohort_run_rate, extra_per_cohort, three_mature_cohorts_run_rate
    ):
        right.text(
            bar.get_width() + 0.7,
            bar.get_y() + bar.get_height() / 2,
            f"€{run_rate / 1000:.1f}k/month\n"
            f"{extra:.0f} extra activations/cohort\n"
            f"€{three_cohorts / 1000:.1f}k/month after 3 matured cohorts",
            va="center",
            fontsize=8.7,
            fontweight="bold",
            color=NAVY,
            linespacing=1.25,
        )
    right.grid(axis="x", color=LIGHT_GREY, linewidth=0.8)
    right.set_axisbelow(True)

    for axis in axes:
        axis.spines[["top", "right", "left"]].set_visible(False)
        axis.tick_params(axis="both", length=0, colors=MID_GREY)

    fig.suptitle(
        "The lever is lasting post-KYB conversion—not simply faster activation",
        x=0.02,
        y=0.985,
        ha="left",
        fontsize=16,
        fontweight="bold",
        color=NAVY,
    )
    fig.text(
        0.02,
        0.925,
        "30-day activation is a leading indicator; the A/B test should use 90-day cumulative revenue per validated company as its primary outcome.",
        ha="left",
        fontsize=9.5,
        color=MID_GREY,
    )
    fig.text(
        0.02,
        0.025,
        f"Observed curve: validation cohorts Oct 2025–Jan 2026 with equal 90-day follow-up (N={int(curve['validated_companies']):,}).  "
        f"Scenario: {validated_per_month:,.0f} validations/month × uplift × persona-weighted April revenue/company. Each cohort needs 90-day follow-up; before cost and not a forecast.",
        ha="left",
        fontsize=7.6,
        color=MID_GREY,
    )
    plt.tight_layout(rect=[0.015, 0.09, 0.995, 0.88], w_pad=3.2)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUTPUT, facecolor="white", bbox_inches="tight")
    plt.close(fig)
    print(OUTPUT)


if __name__ == "__main__":
    build_chart()
