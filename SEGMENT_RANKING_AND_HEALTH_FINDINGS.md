# Segment ranking and mature-company health

## Why add this view

The top-20 result answers how concentrated revenue is, but it does not show the
full trade-off between segment scale, revenue efficiency, and health. The deck
now uses the full 9,088-company comparable base for segment selection and keeps
`20% of companies -> 70% of comparable revenue` as secondary concentration
context.

1. A transparent persona and initial-plan revenue ranking.
2. A 100% stacked health comparison using a mature, comparable company base.

## Revenue ranking

Bar length represents **share of all comparable revenue** across the first three
complete post-activation months. Bar color represents average revenue per
company relative to the overall comparable average of EUR 120.87:

- At least 1.2x: above-average revenue/company.
- 0.8x-1.2x: broadly near average.
- Below 0.8x: below-average revenue/company.

Every bar also shows the eligible company population and average revenue per
company. There is no composite score or top-20 filter, so leadership can see
whether a segment wins through scale, efficiency, or both.

### Personas

| Rank | Persona | Eligible companies | Share of all revenue | Revenue/company index |
|---:|---|---:|---:|---:|
| 1 | BTP | 1,642 | **26.74%** | **1.48x** |
| 2 | Consultant | 1,585 | 15.85% | 0.91x |
| 3 | Others | 1,441 | 12.24% | 0.77x |
| 4 | Retail | 1,254 | 12.19% | 0.88x |
| 5 | Developer IT | 763 | 7.01% | 0.84x |
| 6 | Automobile Trade Repair | 396 | 5.78% | 1.33x |
| 7 | Bikers Drivers | 563 | 4.96% | 0.80x |
| 8 | Wholesale | 210 | 3.36% | 1.45x |

BTP is the strongest scalable persona because it combines the largest revenue
contribution with above-average revenue per company. Automobile Trade Repair
and Wholesale are efficient but materially smaller.

### Initial plans

| Rank | Initial plan | Eligible companies | Share of all revenue | Revenue/company index |
|---:|---|---:|---:|---:|
| 1 | Start | 4,012 | **44.64%** | 1.01x |
| 2 | Plus | 1,286 | **28.56%** | **2.02x** |
| 3 | Free | 3,594 | 19.85% | 0.50x |
| 4 | Business | 196 | 6.95% | **3.22x** |

Start wins on absolute scale at approximately average revenue per company. Plus
has the best scalable efficiency. Business has the highest revenue per company
but is too small and too unhealthy to be the lead recommendation. Free's 19.85%
share shows why the long tail cannot be removed. Only the initial plan is
available, so this ranking does not prove that plan choice causes revenue.

## Why the top 20% is secondary

The top-20 view is still valuable for concentration and targeted protection,
but it changes segment weights:

| Plan | Share of all comparable revenue | Share of top-20 revenue |
|---|---:|---:|
| Start | **44.64%** | 39.70% |
| Plus | 28.56% | **33.42%** |
| Free | **19.85%** | 17.20% |
| Business | 6.95% | **9.67%** |

The 3,237 Start companies outside the top 20% generate EUR 184.0k—37.52% of
all Start revenue and about 56% of all revenue outside the top 20%. The global
bottom half contains 1,747 Start companies generating EUR 53.8k, or 10.97% of
Start revenue. Small companies are not the sole driver, but collectively they
are material.

Therefore, top 20% is used for `70/20` concentration, revenue-type dependence,
and high-value protection. It is not the primary persona or plan ranking.

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
