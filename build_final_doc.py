"""Build the final three-page Shine case memo as a Word document."""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_ALIGN_VERTICAL, WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Inches, Pt, RGBColor


ROOT = Path(__file__).resolve().parent
ASSET_DIR = ROOT / "presentation_assets"
OUTPUT_FILE = ROOT / "Shine_Case_3_Page_Memo.docx"

NAVY = "102A43"
TEAL = "008C8C"
GREEN = "2A9D8F"
AMBER = "E9A23B"
RED = "C95C3D"
LIGHT_BLUE = "EAF4F4"
LIGHT_GREY = "F3F5F7"
MID_GREY = "5E6C76"
WHITE = "FFFFFF"
BLACK = "17212B"


def set_cell_shading(cell, color: str) -> None:
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), color)


def set_cell_margins(cell, top=90, start=110, bottom=90, end=110) -> None:
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for margin, value in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = tc_mar.find(qn(f"w:{margin}"))
        if node is None:
            node = OxmlElement(f"w:{margin}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def set_table_borders(table, color="D8DEE3", size="4") -> None:
    tbl_pr = table._tbl.tblPr
    borders = tbl_pr.first_child_found_in("w:tblBorders")
    if borders is None:
        borders = OxmlElement("w:tblBorders")
        tbl_pr.append(borders)
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        tag = borders.find(qn(f"w:{edge}"))
        if tag is None:
            tag = OxmlElement(f"w:{edge}")
            borders.append(tag)
        tag.set(qn("w:val"), "single")
        tag.set(qn("w:sz"), size)
        tag.set(qn("w:color"), color)


def set_repeat_table_header(row) -> None:
    tr_pr = row._tr.get_or_add_trPr()
    repeat = OxmlElement("w:tblHeader")
    repeat.set(qn("w:val"), "true")
    tr_pr.append(repeat)


def prevent_row_split(row) -> None:
    tr_pr = row._tr.get_or_add_trPr()
    cant_split = OxmlElement("w:cantSplit")
    tr_pr.append(cant_split)


def set_keep_with_next(paragraph, value=True) -> None:
    p_pr = paragraph._p.get_or_add_pPr()
    keep = p_pr.find(qn("w:keepNext"))
    if value and keep is None:
        p_pr.append(OxmlElement("w:keepNext"))


def add_run(paragraph, text, *, bold=False, color=BLACK, size=9.2, italic=False):
    run = paragraph.add_run(text)
    run.bold = bold
    run.italic = italic
    run.font.name = "Arial"
    run.font.size = Pt(size)
    run.font.color.rgb = RGBColor.from_string(color)
    return run


def add_body(document, text, *, bold_prefix=None, size=9.2, space_after=3, color=BLACK):
    paragraph = document.add_paragraph()
    paragraph.paragraph_format.space_after = Pt(space_after)
    paragraph.paragraph_format.line_spacing = 1.04
    if bold_prefix and text.startswith(bold_prefix):
        add_run(paragraph, bold_prefix, bold=True, size=size, color=color)
        add_run(paragraph, text[len(bold_prefix):], size=size, color=color)
    else:
        add_run(paragraph, text, size=size, color=color)
    return paragraph


def add_bullet(document, text, *, level=0, size=8.9, color=BLACK, space_after=1.5):
    paragraph = document.add_paragraph(style="List Bullet" if level == 0 else "List Bullet 2")
    paragraph.paragraph_format.left_indent = Cm(0.45 + 0.35 * level)
    paragraph.paragraph_format.first_line_indent = Cm(-0.22)
    paragraph.paragraph_format.space_after = Pt(space_after)
    paragraph.paragraph_format.line_spacing = 1.0
    add_run(paragraph, text, size=size, color=color)
    return paragraph


def add_heading(document, text, level=1, *, color=NAVY, space_before=4, space_after=3):
    paragraph = document.add_paragraph()
    paragraph.paragraph_format.space_before = Pt(space_before)
    paragraph.paragraph_format.space_after = Pt(space_after)
    paragraph.paragraph_format.keep_with_next = True
    size = 13.2 if level == 1 else 10.6
    add_run(paragraph, text, bold=True, color=color, size=size)
    return paragraph


def add_page_title(document, kicker: str, title: str, subtitle: str) -> None:
    p = document.add_paragraph()
    p.paragraph_format.space_after = Pt(1)
    add_run(p, kicker.upper(), bold=True, color=TEAL, size=8.0)

    p = document.add_paragraph()
    p.paragraph_format.space_after = Pt(1.5)
    p.paragraph_format.keep_with_next = True
    add_run(p, title, bold=True, color=NAVY, size=20)

    p = document.add_paragraph()
    p.paragraph_format.space_after = Pt(6)
    add_run(p, subtitle, color=MID_GREY, size=8.8)


def add_callout(document, text: str, *, fill=NAVY, color=WHITE, size=11.4) -> None:
    table = document.add_table(rows=1, cols=1)
    table.autofit = False
    table.columns[0].width = Cm(18.6)
    cell = table.cell(0, 0)
    set_cell_shading(cell, fill)
    set_cell_margins(cell, top=145, start=180, bottom=145, end=180)
    p = cell.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing = 1.03
    add_run(p, text, bold=True, color=color, size=size)
    document.add_paragraph().paragraph_format.space_after = Pt(0)


def add_kpi_strip(document, items) -> None:
    table = document.add_table(rows=1, cols=len(items))
    table.autofit = False
    for idx, (value, label) in enumerate(items):
        cell = table.cell(0, idx)
        set_cell_shading(cell, LIGHT_GREY if idx % 2 == 0 else LIGHT_BLUE)
        set_cell_margins(cell, top=90, start=65, bottom=90, end=65)
        cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(0)
        add_run(p, value, bold=True, color=TEAL, size=15)
        p = cell.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(0)
        add_run(p, label, color=MID_GREY, size=7.5)
    set_table_borders(table, color=WHITE, size="8")


def add_small_label(cell, text, color=TEAL) -> None:
    p = cell.add_paragraph() if cell.paragraphs[0].text else cell.paragraphs[0]
    p.paragraph_format.space_after = Pt(1)
    add_run(p, text.upper(), bold=True, color=color, size=7.5)


def add_cell_text(cell, text, *, bold=False, size=8.5, color=BLACK, space_after=2):
    p = cell.add_paragraph() if cell.paragraphs[0].text else cell.paragraphs[0]
    p.paragraph_format.space_after = Pt(space_after)
    p.paragraph_format.line_spacing = 1.0
    add_run(p, text, bold=bold, size=size, color=color)
    return p


def add_page_break(document) -> None:
    p = document.add_paragraph()
    p.paragraph_format.space_after = Pt(0)
    p.add_run().add_break()
    p.runs[0]._r.get_or_add_br().set(qn("w:type"), "page")


def add_page_number(paragraph) -> None:
    paragraph.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    add_run(paragraph, "SHINE CASE  •  ", bold=True, color=MID_GREY, size=7.2)
    run = paragraph.add_run()
    fld_char_1 = OxmlElement("w:fldChar")
    fld_char_1.set(qn("w:fldCharType"), "begin")
    instr_text = OxmlElement("w:instrText")
    instr_text.set(qn("xml:space"), "preserve")
    instr_text.text = " PAGE "
    fld_char_2 = OxmlElement("w:fldChar")
    fld_char_2.set(qn("w:fldCharType"), "end")
    run._r.extend((fld_char_1, instr_text, fld_char_2))


def make_concentration_chart(path: Path) -> None:
    from matplotlib.patches import Patch

    fig, ax = plt.subplots(figsize=(7.3, 1.75), dpi=190)
    fig.patch.set_facecolor("white")
    ax.set_facecolor("white")
    labels = ["Share of companies", "Share of revenue (months 1-3)"]
    top = [20, 70.24]
    remainder = [80, 29.76]
    y = [1, 0]
    ax.barh(y, top, color="#008C8C", height=0.48)
    ax.barh(y, remainder, left=top, color="#DCE6EA", height=0.48)
    direct_labels = [
        ("20%", "80%"),
        ("70%", "30%"),
    ]
    for yi, value, (high_label, other_label) in zip(y, top, direct_labels):
        ax.text(value / 2, yi, high_label, ha="center", va="center",
                color="white", fontsize=8.4, fontweight="bold")
        ax.text(value + (100 - value) / 2, yi, other_label,
                ha="center", va="center", color="#425466", fontsize=8.1)
    ax.set_yticks(y, labels, fontsize=8.5, color="#17212B")
    ax.set_xlim(0, 100)
    ax.set_xticks([])
    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.tick_params(axis="y", length=0, pad=7)
    ax.set_title(
        "The highest-revenue 20% of companies generate 70% of comparable revenue",
        loc="left",
        fontsize=9.3,
        fontweight="bold",
        color="#102A43",
        pad=8,
    )
    legend = [
        Patch(facecolor="#008C8C", label="Highest-revenue 20% of companies"),
        Patch(facecolor="#DCE6EA", label="Other 80% of companies"),
    ]
    ax.legend(
        handles=legend,
        ncol=2,
        frameon=False,
        loc="lower center",
        bbox_to_anchor=(0.5, -0.30),
        fontsize=7.3,
        handlelength=1.1,
        columnspacing=1.5,
    )
    plt.tight_layout(rect=[0, 0.13, 1, 1], pad=0.4)
    fig.savefig(path, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def make_health_chart(path: Path) -> None:
    labels = ["Healthy", "Recovered", "At-risk", "Churned proxy"]
    values = [95.08, 0.54, 2.42, 1.96]
    companies = [3341, 19, 85, 69]
    colors = ["#2A9D8F", "#6AAED6", "#E9A23B", "#C95C3D"]
    fig, (ax, detail) = plt.subplots(
        1,
        2,
        figsize=(7.3, 1.55),
        dpi=190,
        gridspec_kw={"width_ratios": [1.05, 1.35]},
    )
    fig.patch.set_facecolor("white")
    comparison_labels = ["Healthy", "Other states"]
    comparison_values = [95.08, 4.92]
    comparison_colors = [colors[0], "#D7E0E5"]
    bars = ax.bar(comparison_labels, comparison_values, color=comparison_colors, width=0.55)
    ax.set_ylim(0, 105)
    ax.set_ylabel("Share of top-20 companies", fontsize=7.2, color="#425466")
    ax.tick_params(axis="x", labelsize=8, length=0)
    ax.tick_params(axis="y", labelsize=6.7, colors="#6B7780", length=0)
    ax.grid(axis="y", color="#E8EDF0", linewidth=0.6)
    ax.set_axisbelow(True)
    for bar, value in zip(bars, comparison_values):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            value + 2,
            f"{value:.1f}%",
            ha="center",
            va="bottom",
            fontsize=9,
            color="#102A43",
            fontweight="bold",
        )
    for spine in ax.spines.values():
        spine.set_visible(False)

    detail.axis("off")
    detail.text(0.00, 0.96, "Exact state breakdown", fontsize=9, fontweight="bold",
                color="#102A43", va="top")
    detail.text(0.38, 0.79, "Companies", fontsize=7, fontweight="bold",
                color="#5E6C76", ha="right")
    detail.text(0.98, 0.79, "Share", fontsize=7, fontweight="bold",
                color="#5E6C76", ha="right")
    row_y = [0.64, 0.47, 0.30, 0.13]
    for y_pos, label, company_count, value, color in zip(
        row_y, labels, companies, values, colors
    ):
        detail.scatter([0.025], [y_pos], s=42, color=color, marker="s")
        detail.text(0.07, y_pos, label, fontsize=7.8, color="#17212B", va="center")
        detail.text(0.38, y_pos, f"{company_count:,}", fontsize=7.8,
                    color="#17212B", va="center", ha="right")
        detail.text(0.98, y_pos, f"{value:.2f}%", fontsize=7.8,
                    color="#17212B", va="center", ha="right", fontweight="bold")
    detail.set_xlim(0, 1)
    detail.set_ylim(0, 1)

    fig.suptitle(
        "Health of 3,514 cumulative top-20 revenue companies as of April",
        x=0.01,
        y=0.99,
        ha="left",
        fontsize=9.3,
        fontweight="bold",
        color="#102A43",
    )
    plt.tight_layout(rect=[0, 0, 1, 0.91], pad=0.35)
    fig.savefig(path, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def configure_document(document: Document) -> None:
    section = document.sections[0]
    section.page_height = Cm(29.7)
    section.page_width = Cm(21.0)
    section.top_margin = Cm(1.15)
    section.bottom_margin = Cm(1.05)
    section.left_margin = Cm(1.25)
    section.right_margin = Cm(1.25)
    section.header_distance = Cm(0.4)
    section.footer_distance = Cm(0.45)

    styles = document.styles
    normal = styles["Normal"]
    normal.font.name = "Arial"
    normal.font.size = Pt(9.2)
    normal.font.color.rgb = RGBColor.from_string(BLACK)
    normal.paragraph_format.space_after = Pt(2)
    normal.paragraph_format.line_spacing = 1.02

    for style_name in ("List Bullet", "List Bullet 2"):
        styles[style_name].font.name = "Arial"
        styles[style_name].font.size = Pt(8.9)

    footer = section.footer
    add_page_number(footer.paragraphs[0])

    document.core_properties.title = "Shine — Revenue Risk & Opportunity"
    document.core_properties.subject = "Senior Data Analyst Case Study"
    document.core_properties.author = "Candidate analysis"


def build_page_one(document: Document, concentration_chart: Path) -> None:
    add_page_title(
        document,
        "Page 1 • Position and magnitude",
        "Shine’s best next-quarter bet is to replicate high-value BTP behavior",
        "Confirmed analysis through April 2026 • May excluded because signup coverage is truncated",
    )
    add_callout(
        document,
        "Across the first three complete calendar months after activation, the highest-revenue "
        "20% of companies generate 70% of revenue. BTP contributes 30% of that value and is "
        "the clearest scalable opportunity.",
    )
    add_kpi_strip(
        document,
        [
            ("20%", "highest-revenue companies"),
            ("70.2%", "revenue in 3 complete months"),
            ("30.3%", "high-value revenue from BTP"),
            ("95.1%", "top-20 accounts Healthy"),
        ],
    )
    p = document.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(3)
    p.paragraph_format.space_after = Pt(1)
    run = p.add_run()
    run.add_picture(str(concentration_chart), width=Cm(17.7))

    method = document.add_table(rows=1, cols=1)
    method.autofit = False
    method.columns[0].width = Cm(18.3)
    cell = method.cell(0, 0)
    set_cell_margins(cell, top=55, start=100, bottom=55, end=100)
    set_cell_shading(cell, LIGHT_GREY)
    add_cell_text(
        cell,
        "Why this window: revenue is supplied only by calendar month. For a company activated "
        "late in month 0, the table cannot separate pre- and post-activation days. We therefore "
        "exclude month 0 and compare months 1-3, the first three complete calendar months. An "
        "exact 90-day window would require daily revenue.",
        size=7.1,
        color=MID_GREY,
    )
    set_table_borders(method, color="DDE3E8", size="4")

    add_heading(document, "What the data shows", level=2, space_before=2)
    table = document.add_table(rows=1, cols=2)
    table.autofit = False
    table.columns[0].width = Cm(9.15)
    table.columns[1].width = Cm(9.15)
    opportunity, risk = table.rows[0].cells
    for cell in (opportunity, risk):
        set_cell_margins(cell, top=105, start=130, bottom=105, end=130)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    set_cell_shading(opportunity, LIGHT_BLUE)
    set_cell_shading(risk, LIGHT_GREY)
    add_small_label(opportunity, "Opportunity", TEAL)
    add_cell_text(opportunity, "BTP is 26.51% of the comparable top 20% and 30.28% of its revenue.", bold=True)
    add_cell_text(opportunity, "Plus is 2.18× overrepresented; BTP + Plus is 2.44× represented.", size=8.2)
    add_small_label(risk, "Risk", RED)
    add_cell_text(risk, "70.7% of April revenue comes from interchange and deposit interest.", bold=True)
    add_cell_text(risk, "The raw top 20% generates ~80% of both streams, creating usage and balance dependence.", size=8.2)
    set_table_borders(table, color=WHITE, size="8")

    add_heading(document, "Definitions and assumptions", level=2, space_before=3)
    definitions = document.add_table(rows=2, cols=2)
    definitions.autofit = False
    definitions.columns[0].width = Cm(9.15)
    definitions.columns[1].width = Cm(9.15)
    text = [
        ("Revenue-active", "revenue row in the observation month"),
        ("Healthy revenue account", "Active with an unbroken revenue streak since activation"),
        ("At-risk", "previously Active, then 1–2 missing revenue months"),
        ("Churned proxy", "previously Active, then ≥3 missing months; not confirmed churn"),
    ]
    for idx, (name, definition) in enumerate(text):
        cell = definitions.cell(idx // 2, idx % 2)
        set_cell_margins(cell, top=55, start=95, bottom=55, end=95)
        p = cell.paragraphs[0]
        p.paragraph_format.space_after = Pt(0)
        add_run(p, f"{name}: ", bold=True, color=NAVY, size=7.8)
        add_run(p, definition, color=MID_GREY, size=7.8)
    set_table_borders(definitions, color="DDE3E8", size="4")

    p = document.add_paragraph()
    p.paragraph_format.space_before = Pt(3)
    p.paragraph_format.space_after = Pt(0)
    add_run(p, "Decision: ", bold=True, color=TEAL, size=9.0)
    add_run(
        p,
        "prioritize a controlled BTP adoption test; protect high-value companies at their first revenue gap. "
        "This is a concentrated growth opportunity—not evidence of a broad churn crisis.",
        size=9.0,
    )


def add_initiative_card(document, rank, title, why, magnitude, limit, fill):
    table = document.add_table(rows=1, cols=4)
    table.autofit = False
    widths = [Cm(1.1), Cm(4.2), Cm(7.4), Cm(5.6)]
    for idx, width in enumerate(widths):
        table.columns[idx].width = width
    cells = table.rows[0].cells
    for cell in cells:
        set_cell_margins(cell, top=100, start=105, bottom=100, end=105)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    set_cell_shading(cells[0], fill)
    p = cells[0].paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_run(p, str(rank), bold=True, color=WHITE, size=16)
    set_cell_shading(cells[1], LIGHT_BLUE if rank == 1 else LIGHT_GREY)
    add_cell_text(cells[1], title, bold=True, size=9.3, color=NAVY)
    add_cell_text(cells[1], why, size=7.8, color=MID_GREY)
    add_small_label(cells[2], "Observable magnitude", TEAL)
    add_cell_text(cells[2], magnitude, size=8.2)
    add_small_label(cells[3], "Limit", RED)
    add_cell_text(cells[3], limit, size=8.0)
    set_table_borders(table, color=WHITE, size="7")
    document.add_paragraph().paragraph_format.space_after = Pt(0)


def build_page_two(document: Document, health_chart: Path) -> None:
    add_page_title(
        document,
        "Page 2 • Ranked decisions",
        "Two initiatives, clearly weighted",
        "Ranked by observable scale, value concentration, health, and actionability",
    )
    add_initiative_card(
        document,
        1,
        "BTP adoption & monetization experiment",
        "Replicate the product behaviors associated with high value; do not assume plan upsell is the lever.",
        "1,642 comparable BTP companies; 482 already top 20%, leaving 1,160 outside. BTP contributes €233.6k / 30.28% of top-20 revenue across the first three complete months.",
        "No current plan, product-use, cost, or margin data. Uplift cannot be sized in euros before a causal test.",
        TEAL,
    )
    add_initiative_card(
        document,
        2,
        "First-gap protection for high-value companies",
        "Trigger support after the first missing revenue month; keep recovered companies monitored.",
        "85 top-20 companies At-risk + 69 Churned proxy. Last-observed monthly revenue exposure: €19.24k. Healthy / recovered pool generates ~€424k in April.",
        "The current eligible risk pool is small and may require a phased rollout or broader pre-defined high-value band.",
        AMBER,
    )

    add_heading(document, "Why blanket churn is not the lead bet", level=2, space_before=2)
    p = document.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(1)
    p.add_run().add_picture(str(health_chart), width=Cm(17.4))

    add_heading(document, "Alternatives considered—and rejected", level=2, space_before=1)
    rows = [
        ("Acquire more Business", "High revenue/company", "Small base; 73.3% funnel dropout; weak continuity; no CAC or KYB-reason data."),
        ("Broad funnel overhaul", "62.9% 30-day dropout", "Cannot distinguish rejection, delay, abandonment, or extraction effects; no channel cost."),
        ("Blanket churn campaign", "Retention feels urgent", "High-value pool is 95.08% Healthy; target the first gap instead."),
        ("Immediate plan upsell", "Plus/Business correlate with value", "Only initial plan exists; current plan and causal plan effect are unknown."),
    ]
    table = document.add_table(rows=1, cols=3)
    table.autofit = False
    widths = [Cm(4.0), Cm(4.1), Cm(10.2)]
    for idx, width in enumerate(widths):
        table.columns[idx].width = width
    headers = ["Alternative", "Why attractive", "Why it loses now"]
    for idx, header in enumerate(headers):
        cell = table.rows[0].cells[idx]
        set_cell_shading(cell, NAVY)
        set_cell_margins(cell, top=70, start=90, bottom=70, end=90)
        add_cell_text(cell, header, bold=True, size=7.8, color=WHITE, space_after=0)
    set_repeat_table_header(table.rows[0])
    for row_values in rows:
        cells = table.add_row().cells
        prevent_row_split(table.rows[-1])
        for idx, value in enumerate(row_values):
            set_cell_margins(cells[idx], top=65, start=90, bottom=65, end=90)
            set_cell_shading(cells[idx], WHITE if len(table.rows) % 2 else LIGHT_GREY)
            add_cell_text(cells[idx], value, bold=(idx == 0), size=7.65, color=NAVY if idx == 0 else BLACK, space_after=0)
    set_table_borders(table, color="D8DEE3", size="3")

    add_heading(document, "Magnitude: honest bounds", level=2, space_before=3)
    add_body(
        document,
        "We can size populations and observed revenue, not incremental uplift. The dataset lacks product usage, current plan, treatment cost, margin, CAC, and a causal counterfactual. Rank 1 has the larger addressable pool; Rank 2 protects a smaller currently exposed pool.",
        size=8.5,
        space_after=0,
    )


def build_page_three(document: Document) -> None:
    add_page_title(
        document,
        "Page 3 • Prove and productionise",
        "Test the lever before scaling—and make the metrics trustworthy",
        "Association identifies where to test; randomisation establishes whether the lever works",
    )

    add_heading(document, "Lead experiment: BTP product adoption", level=2, space_before=0)
    table = document.add_table(rows=5, cols=2)
    table.autofit = False
    table.columns[0].width = Cm(4.0)
    table.columns[1].width = Cm(14.3)
    experiment = [
        ("Hypothesis", "A single, customer-appropriate product-adoption intervention causes incremental recognised revenue without worsening customer, operational, risk, or fairness outcomes."),
        ("Eligibility & design", "Freeze eligibility using a pre-period; use revenue-active BTP below a pre-defined high-value threshold; randomise treatment vs business-as-usual; stratify by pre-revenue, cohort age, current plan and usage; analyse intention-to-treat."),
        ("Primary metric", "Incremental mean total revenue per eligible company over 90 days. Report bootstrap confidence intervals plus median and winsorised sensitivities because revenue is highly skewed."),
        ("Success", "Scale only if the pre-registered interval supports positive uplift above fully loaded treatment cost, with no material guardrail deterioration. Power the test after final eligibility, cost and variance are known."),
        ("Guardrails", "Closures, complaints, support contacts, fraud/AML/risk outcomes, fairness, operational failures, and negative-fee adjustments."),
    ]
    for idx, (label, value) in enumerate(experiment):
        left, right = table.rows[idx].cells
        for cell in (left, right):
            set_cell_margins(cell, top=72, start=95, bottom=72, end=95)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        set_cell_shading(left, LIGHT_BLUE)
        set_cell_shading(right, WHITE if idx % 2 == 0 else LIGHT_GREY)
        add_cell_text(left, label, bold=True, color=TEAL, size=8.0, space_after=0)
        add_cell_text(right, value, size=7.8, space_after=0)
        prevent_row_split(table.rows[idx])
    set_table_borders(table, color="D8DEE3", size="3")

    add_heading(document, "Validate first", level=2, space_before=3)
    validation = document.add_table(rows=1, cols=3)
    validation.autofit = False
    for idx in range(3):
        validation.columns[idx].width = Cm(6.1)
    validations = [
        ("1", "Completeness", "Confirm missing row = zero; reconcile to Finance; keep May out until signup coverage is explained."),
        ("2", "Business meaning", "Validate activation, closure, cancellation, revenue recognition, current plan and persona history."),
        ("3", "KYB & privacy", "Confirm permitted persona use; minimise data; suppress small cells; never use this for adverse eligibility decisions."),
    ]
    for idx, (number, title, detail) in enumerate(validations):
        cell = validation.cell(0, idx)
        set_cell_shading(cell, LIGHT_GREY if idx != 2 else "FBEFEA")
        set_cell_margins(cell, top=90, start=105, bottom=90, end=105)
        p = cell.paragraphs[0]
        p.paragraph_format.space_after = Pt(1)
        add_run(p, number, bold=True, color=TEAL if idx != 2 else RED, size=12)
        add_run(p, f"  {title}", bold=True, color=NAVY, size=8.4)
        add_cell_text(cell, detail, size=7.5, color=BLACK, space_after=0)
    set_table_borders(validation, color=WHITE, size="7")

    add_heading(document, "Trusted production engine", level=2, space_before=3)
    flow = document.add_table(rows=1, cols=7)
    flow.autofit = False
    flow_items = [
        ("Raw", "snapshots"),
        ("→", ""),
        ("Typed", "company-month fact"),
        ("→", ""),
        ("Versioned", "metric marts"),
        ("→", ""),
        ("Governed", "semantic layer"),
    ]
    widths = [Cm(2.55), Cm(0.55), Cm(4.0), Cm(0.55), Cm(3.6), Cm(0.55), Cm(4.7)]
    for idx, width in enumerate(widths):
        flow.columns[idx].width = width
    for idx, (title, subtitle) in enumerate(flow_items):
        cell = flow.cell(0, idx)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        set_cell_margins(cell, top=65, start=45, bottom=65, end=45)
        if title == "→":
            p = cell.paragraphs[0]
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            add_run(p, title, bold=True, color=TEAL, size=12)
        else:
            set_cell_shading(cell, LIGHT_BLUE)
            p = cell.paragraphs[0]
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.space_after = Pt(0)
            add_run(p, title, bold=True, color=NAVY, size=8.0)
            p = cell.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            p.paragraph_format.space_after = Pt(0)
            add_run(p, subtitle, color=MID_GREY, size=6.9)
    set_table_borders(flow, color=WHITE, size="7")

    add_body(
        document,
        "Automated tests: unique company-month key; referential integrity; component-to-total and Finance reconciliation; freshness/completeness; date ordering; state-transition invariants; fixed cohort denominators; late-arriving-data/backfill controls.",
        size=7.75,
        space_after=1,
    )
    add_body(
        document,
        "Ownership: Finance—revenue; Product/Growth—lever and thresholds; Data—models/tests/lineage; Risk/Compliance/Privacy—KYB use; Operations/CRM—execution. Refresh after monthly close and version every definition change.",
        size=7.75,
        space_after=1,
    )

    p = document.add_paragraph()
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after = Pt(0)
    add_run(p, "SQL appendix: ", bold=True, color=TEAL, size=7.7)
    add_run(p, "sql/revenue_concentration_analysis.sql • sql/presentation_kpis.sql • sql/kpi_deep_dive.sql", size=7.7, color=MID_GREY)
    p = document.add_paragraph()
    p.paragraph_format.space_after = Pt(0)
    add_run(p, "Not concluded: ", bold=True, color=RED, size=7.7)
    add_run(p, "true churn, forecast LTV, causal plan effect, CAC/payback, profitability, or complete May performance.", size=7.7, color=MID_GREY)


def build_document() -> Path:
    ASSET_DIR.mkdir(exist_ok=True)
    concentration_chart = ASSET_DIR / "concentration_20_70.png"
    health_chart = ASSET_DIR / "top20_health.png"
    make_concentration_chart(concentration_chart)
    make_health_chart(health_chart)

    document = Document()
    configure_document(document)
    build_page_one(document, concentration_chart)
    document.add_page_break()
    build_page_two(document, health_chart)
    document.add_page_break()
    build_page_three(document)
    document.save(OUTPUT_FILE)
    return OUTPUT_FILE


if __name__ == "__main__":
    output = build_document()
    print(output)
