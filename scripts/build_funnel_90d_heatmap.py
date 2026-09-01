from pathlib import Path

import duckdb
import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import Normalize
from matplotlib.cm import ScalarMappable


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATABASE = PROJECT_ROOT / "data" / "shine_case.duckdb"
OUTPUT = (
    PROJECT_ROOT
    / "outputs"
    / "presentation"
    / "assets"
    / "simple_raw_funnel_90d_heatmap.jpg"
)

NAVY = "#102A43"
MID_GREY = "#526574"
LIGHT_GREY = "#E6ECEF"
CMAP = plt.get_cmap("RdYlGn")

METRIC_COLUMNS = [
    "signup_to_validation_90d_pct",
    "validation_to_activation_90d_pct",
    "signup_to_activation_90d_pct",
]
METRIC_LABELS = [
    "Signup → validation",
    "Validation → activation",
    "Signup → activation",
]


def query_metrics(connection, segment_column=None):
    select_segment = f"{segment_column} AS segment," if segment_column else "'Overall' AS segment,"
    group_by = f"GROUP BY {segment_column}" if segment_column else ""
    return connection.execute(
        f"""
        WITH funnel AS (
            SELECT
                *,
                validation_date BETWEEN company_signup_at::DATE
                                    AND company_signup_at::DATE + INTERVAL 90 DAY
                    AS validated_90d,
                validation_date BETWEEN company_signup_at::DATE
                                    AND company_signup_at::DATE + INTERVAL 90 DAY
                AND activation_date BETWEEN validation_date
                                        AND company_signup_at::DATE + INTERVAL 90 DAY
                    AS activated_90d
            FROM companies
            WHERE company_signup_at >= DATE '2025-10-01'
              AND company_signup_at < DATE '2026-01-31'
        )
        SELECT
            {select_segment}
            COUNT(*) AS n,
            100.0 * COUNT(*) FILTER (WHERE validated_90d)
                / COUNT(*) AS signup_to_validation_90d_pct,
            100.0 * COUNT(*) FILTER (WHERE activated_90d)
                / NULLIF(COUNT(*) FILTER (WHERE validated_90d), 0)
                AS validation_to_activation_90d_pct,
            100.0 * COUNT(*) FILTER (WHERE activated_90d)
                / COUNT(*) AS signup_to_activation_90d_pct
        FROM funnel
        {group_by}
        ORDER BY signup_to_activation_90d_pct DESC
        """
    ).fetchdf()


def clean_label(value):
    label = str(value).replace("_", " ").title()
    return label.replace("Btp", "BTP").replace(" It", " IT")


def normalize_by_column(values):
    normalized = np.zeros_like(values, dtype=float)
    for column_index in range(values.shape[1]):
        column = values[:, column_index]
        minimum = np.nanmin(column)
        maximum = np.nanmax(column)
        if np.isclose(minimum, maximum):
            normalized[:, column_index] = 0.5
        else:
            normalized[:, column_index] = (column - minimum) / (maximum - minimum)
    return normalized


def normalize_across_row(values):
    minimum = np.nanmin(values)
    maximum = np.nanmax(values)
    if np.isclose(minimum, maximum):
        return np.full_like(values, 0.5, dtype=float)
    return (values - minimum) / (maximum - minimum)


def draw_heatmap(ax, frame, title, *, across_row=False, show_column_labels=True):
    values = frame[METRIC_COLUMNS].to_numpy(dtype=float)
    colors = normalize_across_row(values) if across_row else normalize_by_column(values)
    ax.imshow(colors, cmap=CMAP, vmin=0, vmax=1, aspect="auto")

    row_labels = []
    for row in frame.itertuples(index=False):
        marker = "*" if int(row.n) < 100 else ""
        row_labels.append(f"{clean_label(row.segment)}  (N={int(row.n):,}){marker}")

    ax.set_yticks(np.arange(len(frame)), row_labels, fontsize=9.0, color=NAVY)
    ax.set_xticks(np.arange(len(METRIC_LABELS)), METRIC_LABELS)
    ax.tick_params(
        axis="x",
        top=show_column_labels,
        labeltop=show_column_labels,
        bottom=False,
        labelbottom=False,
        length=0,
        pad=7,
        labelsize=9.2,
        colors=NAVY,
    )
    ax.tick_params(axis="y", length=0, pad=7)
    ax.set_title(title, loc="left", fontsize=12, fontweight="bold", color=NAVY, pad=10)

    for row_index in range(values.shape[0]):
        for column_index in range(values.shape[1]):
            shade = colors[row_index, column_index]
            text_color = "white" if shade < 0.17 or shade > 0.83 else "#17212B"
            ax.text(
                column_index,
                row_index,
                f"{values[row_index, column_index]:.1f}%",
                ha="center",
                va="center",
                fontsize=9.3,
                fontweight="bold",
                color=text_color,
            )

    ax.set_xticks(np.arange(-0.5, len(METRIC_LABELS), 1), minor=True)
    ax.set_yticks(np.arange(-0.5, len(frame), 1), minor=True)
    ax.grid(which="minor", color="white", linestyle="-", linewidth=2.0)
    ax.tick_params(which="minor", bottom=False, left=False)
    for spine in ax.spines.values():
        spine.set_visible(False)


def build_chart():
    connection = duckdb.connect(str(DATABASE), read_only=True)
    try:
        overall = query_metrics(connection)
        personas = query_metrics(connection, "persona")
        plans = query_metrics(connection, "initial_subscription_group")
    finally:
        connection.close()

    fig = plt.figure(figsize=(10.6, 11.4), dpi=190, facecolor="white")
    grid = fig.add_gridspec(
        3,
        1,
        height_ratios=[0.75, 7.5, 2.2],
        left=0.30,
        right=0.96,
        top=0.88,
        bottom=0.11,
        hspace=0.62,
    )
    axes = [fig.add_subplot(grid[index, 0]) for index in range(3)]

    draw_heatmap(axes[0], overall, "Overall", across_row=True)
    draw_heatmap(axes[1], personas, "Personas", show_column_labels=True)
    draw_heatmap(axes[2], plans, "Initial plans", show_column_labels=True)

    fig.suptitle(
        "90-day funnel conversion by persona and initial plan — signup cohorts Oct 2025–Jan 2026",
        x=0.04,
        y=0.965,
        ha="left",
        fontsize=17,
        fontweight="bold",
        color=NAVY,
    )

    color_axis = fig.add_axes([0.39, 0.055, 0.32, 0.018])
    colorbar = fig.colorbar(
        ScalarMappable(norm=Normalize(0, 1), cmap=CMAP),
        cax=color_axis,
        orientation="horizontal",
    )
    colorbar.set_ticks([0, 1])
    colorbar.set_ticklabels(["Lower within comparison", "Higher within comparison"])
    colorbar.ax.tick_params(length=0, labelsize=8.2, colors=MID_GREY)
    colorbar.outline.set_visible(False)

    fig.text(
        0.04,
        0.018,
        "Colours are relative: across the Overall row and within each metric column for segments. "
        "They do not represent targets. N is not colour-scaled; * indicates N<100 and should be interpreted cautiously.",
        ha="left",
        fontsize=7.8,
        color=MID_GREY,
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUTPUT, format="jpg", dpi=190, facecolor="white", bbox_inches="tight")
    plt.close(fig)
    print(OUTPUT)


if __name__ == "__main__":
    build_chart()
