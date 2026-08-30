"""Build a three-page Shine memo using only simple base-table queries."""

from pathlib import Path

import duckdb
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Cm, Pt

from build_final_doc import (
    AMBER,
    BLACK,
    LIGHT_BLUE,
    LIGHT_GREY,
    MID_GREY,
    NAVY,
    RED,
    TEAL,
    WHITE,
    add_body,
    add_bullet,
    add_cell_text,
    add_heading,
    add_kpi_strip,
    add_page_title,
    add_run,
    configure_document,
    prevent_row_split,
    set_cell_margins,
    set_cell_shading,
    set_repeat_table_header,
    set_table_borders,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATABASE = PROJECT_ROOT / "data" / "shine_case.duckdb"
ASSET_DIR = PROJECT_ROOT / "outputs" / "presentation" / "assets"
OUTPUT_FILE = (
    PROJECT_ROOT
    / "outputs"
    / "presentation"
    / "Shine_Case_Simple_RAW_3_Page_Memo.docx"
)


def query_frames():
    connection = duckdb.connect(str(DATABASE), read_only=True)
    try:
        april_persona = connection.execute(
            """
            SELECT
                c.persona,
                COUNT(DISTINCT r.company_profile_id) AS revenue_companies,
                SUM(r.total_revenue) AS total_revenue,
                100.0 * SUM(r.total_revenue)
                    / SUM(SUM(r.total_revenue)) OVER () AS revenue_share_pct,
                SUM(r.total_revenue)
                    / COUNT(DISTINCT r.company_profile_id)
                    AS revenue_per_revenue_company
            FROM companies c
            JOIN revenue_with_total r USING (company_profile_id)
            WHERE r.revenue_month = DATE '2026-04-01'
            GROUP BY c.persona
            ORDER BY total_revenue DESC
            """
        ).fetchdf()
        cumulative_persona = connection.execute(
            """
            SELECT
                c.persona,
                COUNT(DISTINCT r.company_profile_id) AS revenue_companies,
                SUM(r.total_revenue) AS total_revenue,
                100.0 * SUM(r.total_revenue)
                    / SUM(SUM(r.total_revenue)) OVER () AS revenue_share_pct,
                SUM(r.total_revenue)
                    / COUNT(DISTINCT r.company_profile_id)
                    AS revenue_per_revenue_company
            FROM companies c
            JOIN revenue_with_total r USING (company_profile_id)
            WHERE r.revenue_month <= DATE '2026-04-01'
            GROUP BY c.persona
            ORDER BY total_revenue DESC
            """
        ).fetchdf()
        april_plan = connection.execute(
            """
            SELECT
                c.initial_subscription_group AS initial_plan,
                COUNT(DISTINCT r.company_profile_id) AS revenue_companies,
                SUM(r.total_revenue) AS total_revenue,
                100.0 * SUM(r.total_revenue)
                    / SUM(SUM(r.total_revenue)) OVER () AS revenue_share_pct,
                SUM(r.total_revenue)
                    / COUNT(DISTINCT r.company_profile_id)
                    AS revenue_per_revenue_company
            FROM companies c
            JOIN revenue_with_total r USING (company_profile_id)
            WHERE r.revenue_month = DATE '2026-04-01'
            GROUP BY c.initial_subscription_group
            ORDER BY total_revenue DESC
            """
        ).fetchdf()
        cumulative_plan = connection.execute(
            """
            SELECT
                c.initial_subscription_group AS initial_plan,
                COUNT(DISTINCT r.company_profile_id) AS revenue_companies,
                SUM(r.total_revenue) AS total_revenue,
                100.0 * SUM(r.total_revenue)
                    / SUM(SUM(r.total_revenue)) OVER () AS revenue_share_pct,
                SUM(r.total_revenue)
                    / COUNT(DISTINCT r.company_profile_id)
                    AS revenue_per_revenue_company
            FROM companies c
            JOIN revenue_with_total r USING (company_profile_id)
            WHERE r.revenue_month <= DATE '2026-04-01'
            GROUP BY c.initial_subscription_group
            ORDER BY total_revenue DESC
            """
        ).fetchdf()
        april_mix = connection.execute(
            """
            SELECT
                SUM(subscription_revenue) AS subscription_revenue,
                SUM(interchange_revenue) AS interchange_revenue,
                SUM(banking_fees) AS banking_fees,
                SUM(deposit_interest_revenue) AS deposit_interest_revenue,
                SUM(total_revenue) AS total_revenue,
                COUNT(DISTINCT company_profile_id) AS revenue_companies
            FROM revenue_with_total
            WHERE revenue_month = DATE '2026-04-01'
            """
        ).fetchdf().iloc[0]
        confirmed_summary = connection.execute(
            """
            SELECT
                SUM(total_revenue) AS total_revenue,
                COUNT(DISTINCT company_profile_id) AS revenue_companies
            FROM revenue_with_total
            WHERE revenue_month <= DATE '2026-04-01'
            """
        ).fetchdf().iloc[0]
        monthly_revenue = connection.execute(
            """
            SELECT
                revenue_month,
                COUNT(DISTINCT company_profile_id) AS revenue_companies,
                SUM(total_revenue) AS total_revenue
            FROM revenue_with_total
            GROUP BY revenue_month
            ORDER BY revenue_month
            """
        ).fetchdf()
        decline = connection.execute(
            """
            WITH company_revenue AS (
                SELECT
                    company_profile_id,
                    SUM(CASE WHEN revenue_month = DATE '2026-03-01'
                        THEN total_revenue ELSE 0 END) AS march_revenue,
                    SUM(CASE WHEN revenue_month = DATE '2026-04-01'
                        THEN total_revenue ELSE 0 END) AS april_revenue
                FROM revenue_with_total
                WHERE revenue_month IN (
                    DATE '2026-03-01', DATE '2026-04-01'
                )
                GROUP BY company_profile_id
            )
            SELECT
                COUNT(*) FILTER (
                    WHERE march_revenue > 0 AND april_revenue > 0
                ) AS active_in_both_months,
                COUNT(*) FILTER (
                    WHERE march_revenue > 0
                      AND april_revenue > 0
                      AND april_revenue <= 0.70 * march_revenue
                      AND march_revenue - april_revenue >= 10
                ) AS material_decline_companies,
                100.0 * COUNT(*) FILTER (
                    WHERE march_revenue > 0
                      AND april_revenue > 0
                      AND april_revenue <= 0.70 * march_revenue
                      AND march_revenue - april_revenue >= 10
                ) / COUNT(*) FILTER (
                    WHERE march_revenue > 0 AND april_revenue > 0
                ) AS material_decline_share_pct,
                COUNT(*) FILTER (
                    WHERE march_revenue > 0 AND april_revenue = 0
                ) AS first_observed_gap_in_april
            FROM company_revenue
            """
        ).fetchdf().iloc[0]
        return (
            april_persona,
            cumulative_persona,
            april_plan,
            cumulative_plan,
            april_mix,
            confirmed_summary,
            monthly_revenue,
            decline,
        )
    finally:
        connection.close()


def clean_label(value):
    label = str(value).replace("_", " ").title()
    return label.replace("Btp", "BTP").replace(" It", " IT")


def make_segment_chart(cumulative_persona, cumulative_plan, output_path):
    persona = cumulative_persona.head(8).iloc[::-1].copy()
    plan = cumulative_plan.iloc[::-1].copy()
    fig, axes = plt.subplots(1, 2, figsize=(12.4, 4.7), gridspec_kw={"width_ratios": [1.45, 1]})
    fig.patch.set_facecolor("white")

    persona_colors = ["#008C8C" if value == "BTP" else "#A9C7C7" for value in persona["persona"]]
    bars = axes[0].barh(
        [clean_label(value) for value in persona["persona"]],
        persona["revenue_share_pct"],
        color=persona_colors,
        height=0.62,
    )
    for bar, share in zip(bars, persona["revenue_share_pct"]):
        axes[0].text(
            bar.get_width() + 0.35,
            bar.get_y() + bar.get_height() / 2,
            f"{share:.1f}%",
            va="center",
            fontsize=9,
            fontweight="bold",
            color="#17212B",
        )
    axes[0].set_title("Confirmed revenue share by persona", loc="left", fontsize=12, fontweight="bold", color="#102A43")
    axes[0].set_xlabel("Share of cumulative revenue through April", fontsize=9, color="#5E6C76")
    axes[0].set_xlim(0, max(persona["revenue_share_pct"]) * 1.22)

    plan_colors = ["#008C8C" if value == "plus" else "#A9C7C7" for value in plan["initial_plan"]]
    bars = axes[1].barh(
        [clean_label(value) for value in plan["initial_plan"]],
        plan["revenue_share_pct"],
        color=plan_colors,
        height=0.58,
    )
    for bar, share, average in zip(
        bars,
        plan["revenue_share_pct"],
        plan["revenue_per_revenue_company"],
    ):
        axes[1].text(
            bar.get_width() + 0.45,
            bar.get_y() + bar.get_height() / 2,
            f"{share:.1f}%  |  €{average:.0f}/company",
            va="center",
            fontsize=8.3,
            fontweight="bold",
            color="#17212B",
        )
    axes[1].set_title("Confirmed revenue by initial plan", loc="left", fontsize=12, fontweight="bold", color="#102A43")
    axes[1].set_xlabel("Share of cumulative revenue through April", fontsize=9, color="#5E6C76")
    axes[1].set_xlim(0, max(plan["revenue_share_pct"]) * 1.72)

    for axis in axes:
        axis.spines[["top", "right", "left"]].set_visible(False)
        axis.grid(axis="x", color="#E4E9ED", linewidth=0.7)
        axis.set_axisbelow(True)
        axis.tick_params(axis="y", length=0, labelsize=8.5)
        axis.tick_params(axis="x", labelsize=8, colors="#5E6C76")

    fig.text(
        0.01,
        0.005,
        "Bar length = share of confirmed cumulative revenue through April. Plan labels also show cumulative revenue per revenue-producing company. BTP and Plus highlighted.",
        fontsize=8,
        color="#5E6C76",
    )
    plt.tight_layout(rect=(0, 0.05, 1, 1))
    fig.savefig(output_path, dpi=190, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def make_trend_decline_chart(monthly_revenue, decline, output_path):
    months = monthly_revenue.copy()
    months["month_label"] = months["revenue_month"].dt.strftime("%b %y")
    months["revenue_thousands"] = months["total_revenue"] / 1000

    active_both = int(decline["active_in_both_months"])
    material_decline = int(decline["material_decline_companies"])
    april_gap = int(decline["first_observed_gap_in_april"])
    active_no_material_decline = active_both - material_decline

    fig, axes = plt.subplots(
        1,
        2,
        figsize=(12.4, 4.4),
        gridspec_kw={"width_ratios": [1.45, 1]},
    )
    fig.patch.set_facecolor("white")

    colors = ["#008C8C"] * (len(months) - 1) + ["#E9A23B"]
    bars = axes[0].bar(
        months["month_label"],
        months["revenue_thousands"],
        color=colors,
        width=0.68,
    )
    bars[-1].set_hatch("///")
    bars[-1].set_edgecolor("#A56B12")
    for index, (bar, value) in enumerate(zip(bars, months["revenue_thousands"])):
        axes[0].text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + 10,
            f"€{value:.0f}k",
            ha="center",
            va="bottom",
            fontsize=8.2,
            fontweight="bold",
            color="#A56B12" if index == len(bars) - 1 else "#17212B",
        )
    axes[0].text(
        len(months) - 1,
        months["revenue_thousands"].iloc[-1] * 0.55,
        "PROVISIONAL",
        ha="center",
        va="center",
        rotation=90,
        fontsize=7.5,
        fontweight="bold",
        color="white",
    )
    axes[0].set_title(
        "Monthly recognized revenue",
        loc="left",
        fontsize=12,
        fontweight="bold",
        color="#102A43",
    )
    axes[0].set_ylabel("Revenue (€ thousands)", fontsize=9, color="#5E6C76")
    axes[0].set_ylim(0, max(months["revenue_thousands"]) * 1.18)
    axes[0].tick_params(axis="x", rotation=35)

    labels = [
        "Active both;\nno material decline",
        "Active both;\n≥30% and €10 decline",
        "March revenue;\nno April row",
    ]
    values = [active_no_material_decline, material_decline, april_gap]
    decline_colors = ["#A9C7C7", "#E9A23B", "#C95C3D"]
    decline_bars = axes[1].barh(labels[::-1], values[::-1], color=decline_colors[::-1], height=0.58)
    for bar, value in zip(decline_bars, values[::-1]):
        axes[1].text(
            bar.get_width() + 180,
            bar.get_y() + bar.get_height() / 2,
            f"{value:,}",
            va="center",
            fontsize=9,
            fontweight="bold",
            color="#17212B",
        )
    axes[1].set_title(
        "Simple March → April screen",
        loc="left",
        fontsize=12,
        fontweight="bold",
        color="#102A43",
    )
    axes[1].set_xlabel("Companies", fontsize=9, color="#5E6C76")
    axes[1].set_xlim(0, max(values) * 1.20)

    for axis in axes:
        axis.spines[["top", "right", "left"]].set_visible(False)
        axis.grid(axis="y" if axis is axes[0] else "x", color="#E4E9ED", linewidth=0.7)
        axis.set_axisbelow(True)
        axis.tick_params(axis="y", length=0, labelsize=8.3)
        axis.tick_params(axis="x", labelsize=8, colors="#5E6C76")

    fig.text(
        0.01,
        0.005,
        "May is retained as a provisional sensitivity. The decline screen is diagnostic only: a decline or missing row is not confirmed churn.",
        fontsize=8,
        color="#5E6C76",
    )
    plt.tight_layout(rect=(0, 0.06, 1, 1))
    fig.savefig(output_path, dpi=190, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def add_code_box(document, lines, caption):
    table = document.add_table(rows=1, cols=1)
    table.autofit = False
    table.columns[0].width = Cm(18.3)
    cell = table.cell(0, 0)
    set_cell_shading(cell, LIGHT_GREY)
    set_cell_margins(cell, top=75, start=115, bottom=75, end=115)
    p = cell.paragraphs[0]
    p.paragraph_format.space_after = Pt(2)
    add_run(p, caption, bold=True, color=TEAL, size=7.5)
    for index, line in enumerate(lines):
        p = cell.add_paragraph() if index or p.text else p
        p.paragraph_format.space_after = Pt(0)
        add_run(p, line, color=BLACK, size=6.8)
    set_table_borders(table, color="D8DEE3", size="3")


def build_page_one(
    document,
    chart,
    april_persona,
    cumulative_persona,
    cumulative_plan,
    april_mix,
    confirmed_summary,
):
    btp_april = april_persona.loc[april_persona["persona"] == "BTP"].iloc[0]
    btp_cumulative = cumulative_persona.loc[cumulative_persona["persona"] == "BTP"].iloc[0]
    start = cumulative_plan.loc[cumulative_plan["initial_plan"] == "start"].iloc[0]
    plus = cumulative_plan.loc[cumulative_plan["initial_plan"] == "plus"].iloc[0]
    add_page_title(
        document,
        "Page 1 • Raw-data big picture",
        "BTP leads the full confirmed revenue view; Start leads plan scale",
        "Base tables only • Cumulative through April 2026 • May excluded from headlines",
    )
    add_kpi_strip(
        document,
        [
            (f"€{confirmed_summary['total_revenue'] / 1_000_000:.2f}m", "confirmed revenue through April"),
            (f"{int(confirmed_summary['revenue_companies']):,}", "companies with confirmed revenue"),
            (f"{btp_cumulative['revenue_share_pct']:.1f}%", "confirmed revenue from BTP"),
            (f"{start['revenue_share_pct']:.1f}%", "confirmed revenue from Start"),
        ],
    )
    p = document.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after = Pt(1)
    p.add_run().add_picture(str(chart), width=Cm(18.0))

    add_heading(document, "What I conclude", level=2, space_before=2)
    table = document.add_table(rows=1, cols=3)
    table.autofit = False
    for idx, width in enumerate((Cm(6.1), Cm(6.1), Cm(6.1))):
        table.columns[idx].width = width
    cards = [
        ("BTP", f"Largest confirmed persona at {btp_cumulative['revenue_share_pct']:.2f}%; April independently shows {btp_april['revenue_share_pct']:.2f}%, so the result is not driven by one view.", TEAL),
        ("Start vs Plus", f"Start supplies {start['revenue_share_pct']:.2f}% through scale; Plus supplies {plus['revenue_share_pct']:.2f}% at €{plus['revenue_per_revenue_company']:.2f} cumulative revenue per revenue company.", NAVY),
        ("Current economics", "In April, interchange is 42.0% and deposit interest 28.7% of revenue; subscriptions alone are 21.0%.", AMBER),
    ]
    for idx, (title, body, color) in enumerate(cards):
        cell = table.cell(0, idx)
        set_cell_shading(cell, LIGHT_BLUE if idx == 0 else LIGHT_GREY)
        set_cell_margins(cell, top=95, start=110, bottom=95, end=110)
        add_cell_text(cell, title, bold=True, color=color, size=8.7)
        add_cell_text(cell, body, size=7.8, space_after=0)
    set_table_borders(table, color=WHITE, size="7")

    add_code_box(
        document,
        [
            "SELECT c.persona, SUM(r.total_revenue),",
            "       100 * SUM(r.total_revenue) / SUM(SUM(r.total_revenue)) OVER ()",
            "FROM companies c JOIN revenue_with_total r USING (company_profile_id)",
            "WHERE r.revenue_month <= DATE '2026-04-01' GROUP BY c.persona;",
        ],
        "Core query pattern",
    )


def add_initiative(document, number, title, evidence, action, limit, color):
    table = document.add_table(rows=1, cols=4)
    table.autofit = False
    for idx, width in enumerate((Cm(1.1), Cm(4.1), Cm(7.0), Cm(6.1))):
        table.columns[idx].width = width
    cells = table.rows[0].cells
    for cell in cells:
        set_cell_margins(cell, top=95, start=105, bottom=95, end=105)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    set_cell_shading(cells[0], color)
    p = cells[0].paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_run(p, str(number), bold=True, color=WHITE, size=16)
    set_cell_shading(cells[1], LIGHT_BLUE if number == 1 else LIGHT_GREY)
    add_cell_text(cells[1], title, bold=True, color=NAVY, size=9.0)
    add_cell_text(cells[1], action, size=7.8, color=MID_GREY, space_after=0)
    add_cell_text(cells[2], "Raw evidence", bold=True, color=TEAL, size=7.8)
    add_cell_text(cells[2], evidence, size=8.0, space_after=0)
    add_cell_text(cells[3], "Important limit", bold=True, color=RED, size=7.8)
    add_cell_text(cells[3], limit, size=7.8, space_after=0)
    set_table_borders(table, color=WHITE, size="7")
    document.add_paragraph().paragraph_format.space_after = Pt(0)


def build_page_two(document, trend_decline_chart, april_persona, cumulative_persona, decline):
    btp_april = april_persona.loc[april_persona["persona"] == "BTP"].iloc[0]
    btp_cumulative = cumulative_persona.loc[cumulative_persona["persona"] == "BTP"].iloc[0]
    add_page_title(
        document,
        "Page 2 • Ranked actions",
        "Use simple evidence to choose where to test—not to claim causality",
        "Two initiatives, clearly weighted",
    )
    add_initiative(
        document,
        1,
        "BTP-fit activation test",
        f"BTP is {btp_april['revenue_share_pct']:.2f}% of April revenue and {btp_cumulative['revenue_share_pct']:.2f}% of cumulative confirmed revenue.",
        "Test one relevant workflow—such as invoicing, collection, expense control, or cash-flow alerts—against business-as-usual.",
        "Raw revenue cannot show product use, CAC, margin, current plan, or whether existing BTP marketing created the result.",
        TEAL,
    )
    add_initiative(
        document,
        2,
        "Revenue-decline diagnosis",
        f"{int(decline['material_decline_companies']):,} of {int(decline['active_in_both_months']):,} March-April active companies ({decline['material_decline_share_pct']:.2f}%) fell ≥30% and €10; {int(decline['first_observed_gap_in_april']):,} had a first April gap.",
        "Use the decline as a diagnostic trigger and investigate the first missing-revenue month; monitor recoveries separately.",
        "Two months are noisy. This is not churn, forecast loss, or proof that outreach will recover revenue.",
        AMBER,
    )

    p = document.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after = Pt(1)
    p.add_run().add_picture(str(trend_decline_chart), width=Cm(17.6))

    add_heading(document, "Alternatives considered", level=2, space_before=3)
    alternatives = [
        ("Acquire Business", "High revenue/company, but only 262 April revenue companies and 6.79% of April revenue."),
        ("Immediate plan upsell", "Initial plan is not current plan and correlation is not a causal effect."),
        ("Blanket churn campaign", "A decline, revenue gap, or company closure does not prove customer churn."),
        ("Headline May", "May revenue is retained as sensitivity, but signup coverage is incomplete."),
    ]
    table = document.add_table(rows=1, cols=2)
    table.autofit = False
    table.columns[0].width = Cm(4.6)
    table.columns[1].width = Cm(13.7)
    for idx, header in enumerate(("Alternative", "Why it is not the lead")):
        cell = table.rows[0].cells[idx]
        set_cell_shading(cell, NAVY)
        set_cell_margins(cell, top=65, start=90, bottom=65, end=90)
        add_cell_text(cell, header, bold=True, color=WHITE, size=7.8, space_after=0)
    set_repeat_table_header(table.rows[0])
    for row_index, values in enumerate(alternatives):
        cells = table.add_row().cells
        prevent_row_split(table.rows[-1])
        for idx, value in enumerate(values):
            set_cell_shading(cells[idx], WHITE if row_index % 2 == 0 else LIGHT_GREY)
            set_cell_margins(cells[idx], top=52, start=85, bottom=52, end=85)
            add_cell_text(cells[idx], value, bold=(idx == 0), color=NAVY if idx == 0 else BLACK, size=7.4, space_after=0)
    set_table_borders(table, color="D8DEE3", size="3")

def build_page_three(document):
    add_page_title(
        document,
        "Page 3 • Transparency and proof",
        "Start simple; use advanced SQL to test whether the story survives",
        "Raw numbers remain the entry point—the model is the validation layer",
    )
    add_heading(document, "What each layer answers", level=2, space_before=0)
    rows = [
        ("Largest persona", "April and cumulative GROUP BY", "Equal-tenure first 3 complete months", "sql/revenue_concentration_analysis.sql"),
        ("Revenue concentration", "Not used to pick the segment", "Top-10/top-20 and Pareto sensitivities", "sql/revenue_concentration_analysis.sql"),
        ("Account health", "March-to-April decline", "Trailing median + continuity states", "sql/presentation_kpis.sql"),
        ("Inactivity", "Missing revenue row", "Return curve and lifecycle states", "sql/kpi_deep_dive.sql"),
        ("Cohorts", "Not answered", "Equal-age cohort transitions", "sql/cohort_state_analysis.sql"),
        ("Loyalty", "Not answered", "Streak persistence and restart", "sql/streak_analysis.sql"),
    ]
    table = document.add_table(rows=1, cols=4)
    table.autofit = False
    for idx, width in enumerate((Cm(3.3), Cm(4.2), Cm(5.0), Cm(5.8))):
        table.columns[idx].width = width
    for idx, header in enumerate(("Question", "Simple view", "Advanced check", "Where")):
        cell = table.rows[0].cells[idx]
        set_cell_shading(cell, NAVY)
        set_cell_margins(cell, top=70, start=85, bottom=70, end=85)
        add_cell_text(cell, header, bold=True, color=WHITE, size=7.6, space_after=0)
    set_repeat_table_header(table.rows[0])
    for row_index, values in enumerate(rows):
        cells = table.add_row().cells
        prevent_row_split(table.rows[-1])
        for idx, value in enumerate(values):
            set_cell_shading(cells[idx], WHITE if row_index % 2 == 0 else LIGHT_GREY)
            set_cell_margins(cells[idx], top=55, start=80, bottom=55, end=80)
            add_cell_text(cells[idx], value, bold=(idx == 0), color=NAVY if idx == 0 else BLACK, size=7.1, space_after=0)
    set_table_borders(table, color="D8DEE3", size="3")

    add_heading(document, "The useful triangulation", level=2, space_before=3)
    table = document.add_table(rows=1, cols=3)
    table.autofit = False
    for idx in range(3):
        table.columns[idx].width = Cm(6.1)
    checks = [
        ("24.06%", "BTP share in April", "simple current snapshot"),
        ("25.42%", "BTP share through April", "simple cumulative view"),
        ("26.74%", "BTP equal-tenure share", "advanced confirmation"),
    ]
    for idx, (number, label, note) in enumerate(checks):
        cell = table.cell(0, idx)
        set_cell_shading(cell, LIGHT_BLUE if idx == 2 else LIGHT_GREY)
        set_cell_margins(cell, top=105, start=110, bottom=105, end=110)
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        add_run(p, number, bold=True, color=TEAL if idx == 2 else NAVY, size=16)
        p = cell.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        add_run(p, label, bold=True, color=BLACK, size=8.0)
        p = cell.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        add_run(p, note, color=MID_GREY, size=7.0)
    set_table_borders(table, color=WHITE, size="7")

    add_heading(document, "Lead experiment and validation", level=2, space_before=3)
    add_bullet(document, "Randomise eligible BTP companies to one defined workflow versus business-as-usual; do not target on persona alone.", size=8.0)
    add_bullet(document, "Measure incremental recognized revenue over 90 days, feature adoption, and account-health guardrails.", size=8.0)
    add_bullet(document, "Validate missing-row meaning, current plan, product use, channel/CAC, margin, BTP definition, and permitted KYB use.", size=8.0)

    p = document.add_paragraph()
    p.paragraph_format.space_before = Pt(3)
    p.paragraph_format.space_after = Pt(1)
    add_run(p, "Simple SQL appendix: ", bold=True, color=TEAL, size=7.7)
    add_run(p, "sql/simple_raw_memo_queries.sql", color=BLACK, size=7.7)
    p = document.add_paragraph()
    p.paragraph_format.space_after = Pt(1)
    add_run(p, "Advanced SQL: ", bold=True, color=TEAL, size=7.7)
    add_run(p, "revenue_concentration_analysis.sql • presentation_kpis.sql • cohort_state_analysis.sql • streak_analysis.sql • kpi_deep_dive.sql", color=MID_GREY, size=7.4)
    p = document.add_paragraph()
    p.paragraph_format.space_after = Pt(0)
    add_run(p, "External context: ", bold=True, color=TEAL, size=7.7)
    add_run(p, "docs/research/SHINE_MARKET_RESEARCH_AND_STRATEGY.md", color=MID_GREY, size=7.4)


def build_document():
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    (
        april_persona,
        cumulative_persona,
        _april_plan,
        cumulative_plan,
        april_mix,
        confirmed_summary,
        monthly_revenue,
        decline,
    ) = query_frames()
    chart = ASSET_DIR / "simple_raw_segment_view.png"
    trend_decline_chart = ASSET_DIR / "simple_raw_trend_and_decline.png"
    make_segment_chart(cumulative_persona, cumulative_plan, chart)
    make_trend_decline_chart(monthly_revenue, decline, trend_decline_chart)

    document = Document()
    configure_document(document)
    document.core_properties.title = "Shine — Simple raw-data revenue memo"
    document.core_properties.subject = "Three-page memo using base tables and simple SQL"
    build_page_one(
        document,
        chart,
        april_persona,
        cumulative_persona,
        cumulative_plan,
        april_mix,
        confirmed_summary,
    )
    document.add_page_break()
    build_page_two(
        document,
        trend_decline_chart,
        april_persona,
        cumulative_persona,
        decline,
    )
    document.add_page_break()
    build_page_three(document)
    document.save(OUTPUT_FILE)
    return OUTPUT_FILE


if __name__ == "__main__":
    print(build_document())
