# Segment ranking and mature-company health

## Why add this view

The top-20 result answers how concentrated revenue is, but it does not show the
full trade-off between segment scale, revenue efficiency, and health. The deck
now keeps `20% of companies -> 70% of comparable revenue` as a headline and adds
two decision views:

1. A transparent persona and initial-plan revenue ranking.
2. A 100% stacked health comparison using a mature, comparable company base.

## Revenue ranking

Bar length represents **share of all high-value revenue** across the first three
complete post-activation months. Bar color represents the segment's company
representation in the high-value pool:

- At least 1.2x: overrepresented.
- 0.8x-1.2x: broadly proportional.
- Below 0.8x: underrepresented.

Every bar also shows the eligible company population. There is no composite
score, so leadership can see whether a segment wins through scale, efficiency,
or both.

### Personas

| Rank | Persona | Eligible companies | Share of high-value revenue | Representation |
|---:|---|---:|---:|---:|
| 1 | BTP | 1,642 | **30.28%** | **1.47x** |
| 2 | Consultant | 1,585 | 14.91% | 0.86x |
| 3 | Retail | 1,254 | 11.57% | 0.80x |
| 4 | Others | 1,441 | 10.68% | 0.77x |
| 5 | Automobile Trade Repair | 396 | 6.45% | 1.36x |
| 6 | Developer IT | 763 | 6.35% | 1.03x |
| 7 | Bikers Drivers | 563 | 4.50% | 0.84x |
| 8 | Wholesale | 210 | 3.79% | 1.38x |

BTP is the strongest scalable persona because it combines the largest revenue
contribution with above-base high-value representation. Automobile Trade Repair
and Wholesale are efficient but materially smaller.

### Initial plans

| Rank | Initial plan | Eligible companies | Share of high-value revenue | Representation |
|---:|---|---:|---:|---:|
| 1 | Start | 4,012 | 39.70% | 0.97x |
| 2 | Plus | 1,286 | **33.42%** | **2.18x** |
| 3 | Free | 3,594 | 17.20% | 0.48x |
| 4 | Business | 196 | 9.67% | **3.55x** |

Start wins on absolute scale but is only proportional to its base. Plus has the
best scalable efficiency. Business has the highest representation but is too
small and too unhealthy to be the lead recommendation. Only the initial plan is
available, so this ranking does not prove that plan choice causes revenue.

## Comparable mature-company health

Using the entire April population would make almost 60% `Insufficient history`
because the company base is growing rapidly. That would obscure real segment
differences. The stacked bars therefore use **6,337 companies activated by
December 2025**, giving every company three complete post-activation months
before April.

The bars show percentages for comparability and label the segment population
to preserve scale. They are sorted by `Watch + At-risk + Churned proxy`.

### Overall mature-base health

| State | Companies | Share |
|---|---:|---:|
| Healthy | 4,735 | 74.72% |
| Watch | 673 | 10.62% |
| Recovered | 94 | 1.48% |
| At-risk | 280 | 4.42% |
| Churned proxy | 538 | 8.49% |
| Never monetized | 17 | 0.27% |

### Initial-plan contrast

| Plan | Mature companies | Healthy | Watch | At-risk + Churned proxy |
|---|---:|---:|---:|---:|
| Business | 143 | **46.15%** | 10.49% | **43.36%** |
| Plus | 929 | 64.05% | **15.29%** | 18.08% |
| Start | 2,801 | 76.83% | 11.78% | 10.21% |
| Free | 2,464 | **78.00%** | 7.55% | 12.25% |

Business is a high-value but fragile niche. Plus is the more scalable monetized
pool, but its health is weaker than Start and Free. That supports a controlled
Plus/BTP adoption test with health guardrails rather than an immediate broad
upsell.

### Persona contrast

| Persona | Mature companies | Healthy | Watch | Watch + inactive |
|---|---:|---:|---:|---:|
| Automobile Trade Repair | 270 | 62.59% | 16.67% | **35.56%** |
| Bikers Drivers | 409 | 62.59% | 9.54% | **34.73%** |
| BTP | 1,151 | 71.07% | **15.55%** | 27.80% |
| Wholesale | 152 | 71.71% | 13.16% | 25.66% |
| Retail | 865 | 73.29% | 9.94% | 24.62% |
| Others | 1,004 | 76.00% | 8.47% | 22.51% |
| Consultant | 1,097 | **80.40%** | 8.84% | 18.23% |
| Developer IT | 552 | **80.07%** | 8.88% | 17.76% |

BTP is not the healthiest persona, but it remains the best balanced candidate
because it combines large revenue scale, positive representation, and a large
actionable Watch population. Consultant and Developer IT provide useful strong
benchmarks. Automobile Trade Repair and Bikers Drivers deserve diagnostic work,
but they are weaker candidates for the lead growth initiative.

## Caveats

- `Watch` is an analytical revenue-decline signal, not churn.
- `Churned proxy` is based on three missing revenue months, not cancellation.
- The source lacks product usage, balances, transactions, current plan, costs,
  and margin, so drivers and euro uplift cannot be established.
- Persona and initial plan are associations, not causal treatment levers.
- Small segments must not be ranked from percentages without displaying `N`.

## Supporting outputs

- `eda_outputs/eda_segment_opportunity_ranking.csv`
- `eda_outputs/eda_comparable_account_health_by_segment.csv`
- `sql/presentation_kpis.sql`
- `presentation_assets/segment_opportunity_ranking.png`
- `presentation_assets/segment_health_stacked.png`
