# Shine Senior Data Analyst case

This repository contains the raw case data, reproducible DuckDB analysis,
generated EDA outputs, written findings, and presentation deliverables.

## Repository structure

```text
shine-case/
├── data/                 # Generated DuckDB database
├── dataset/              # Raw source CSV files (kept unchanged)
├── docs/
│   ├── data-quality/     # Data-quality questions and inconsistencies
│   ├── findings/         # EDA, cohort, health, streak, and concentration notes
│   ├── guides/           # DuckDB usage guide
│   ├── presentation/     # Final presentation framework
│   ├── research/         # External market research with linked sources
│   └── source/           # Original case-study briefing
├── outputs/
│   ├── eda/              # Generated CSV analysis tables
│   ├── presentation/     # Three-page memo and chart assets
│   └── research/         # Formatted external-research document
├── scripts/              # Python runners and document builders
├── sql/                  # Reproducible EDA and editable query templates
└── README.md
```

## Main deliverables

- `outputs/presentation/Shine_Case_3_Page_Memo.docx`
- `outputs/presentation/Shine_Case_Simple_RAW_3_Page_Memo.docx`
- `outputs/research/Shine_External_Market_Research_and_Revised_Strategy.docx`
- `docs/presentation/FINAL_PRESENTATION_KPI_FRAMEWORK.md`
- `docs/presentation/SIMPLE_RAW_MEMO.md`
- `docs/research/SHINE_MARKET_RESEARCH_AND_STRATEGY.md`
- `docs/data-quality/dataset-data-quality-questions.md`

## Run the analysis

From the repository root:

```powershell
python scripts/run_eda.py
```

This rebuilds `data/shine_case.duckdb` and refreshes `outputs/eda/`.

Run the editable SQL playground:

```powershell
python scripts/run_query.py
```

Or pass another SQL file:

```powershell
python scripts/run_query.py sql/cohort_playground.sql
```

Rebuild the Word documents:

```powershell
python scripts/build_final_doc.py
python scripts/build_simple_raw_memo.py
python scripts/build_market_research_doc.py
```

More detail is available in `docs/guides/DUCKDB_GUIDE.md`.
