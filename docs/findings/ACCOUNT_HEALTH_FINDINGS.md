# Account health: continuity plus revenue momentum

## What changed

The previous `Healthy revenue account` definition used revenue streaks only. It
meant active in April with revenue in every observed month since activation.
That is better described as **continuously monetized**: it does not prove that
the account's revenue is stable.

The revised framework keeps lifecycle and momentum separate, then combines
them into a presentation health state.

## Definitions

| State | Operational definition |
|---|---|
| Continuously monetized | Revenue-active in April with no earlier missing revenue month since activation. |
| Healthy revenue account | Continuously monetized, three prior complete months available, and no material revenue-decline warning. |
| Watch - revenue declining | Continuously monetized, but April revenue is at least 30% and EUR 10 below the median of the previous three complete calendar months. |
| Recovered / monitor | Revenue-active in April after at least one earlier revenue gap. |
| Insufficient history | Active with no gap, but fewer than three prior complete post-activation months. |
| At-risk | Previously monetized and now missing revenue for one or two months. |
| Churned proxy | Previously monetized and now missing revenue for at least three months. This is not confirmed customer churn. |

Revenue momentum does not redefine churn. `Watch` is an early-warning diagnostic
for an account that is still active; `At-risk` and `Churned proxy` are based on
missing revenue months.

## Why this baseline

The revenue source has one row per calendar month, not daily revenue. Activation
month can therefore represent anything from one day to a full month of exposure.
The momentum baseline excludes activation month and uses the median of the three
most recent complete calendar months before April.

Median reduces sensitivity to a single previous spike. The 30% relative decline
is the midpoint of the tested 20%/30%/40% range, and the EUR 10 floor prevents a
large percentage change on a tiny value from creating a warning. Both thresholds
remain assumptions that should be calibrated with Finance and Product.

## High-value result

The population is the 3,514 companies in the cumulative top 20% of revenue
through April.

| Health state | Companies | Share of high-value population |
|---|---:|---:|
| Healthy revenue account | 1,631 | 46.41% |
| Watch - revenue declining | 493 | 14.03% |
| Insufficient history | 1,217 | 34.63% |
| Recovered / monitor | 19 | 0.54% |
| At-risk | 85 | 2.42% |
| Churned proxy | 69 | 1.96% |

The correct momentum denominator is the **2,124** continuously monetized
high-value accounts with sufficient history:

- **76.79% Healthy**: 1,631 companies.
- **23.21% Watch**: 493 companies.

The Watch companies generated EUR 29.8k in April versus a summed trailing
monthly median baseline of EUR 70.8k. The EUR 41.0k difference is an observed
monthly gap—not forecast loss, preventable churn, or a causal estimate of
recoverable revenue.

The original 95.08% remains valid only as a continuity statistic: 3,341
high-value companies are active with no previous revenue gap. It should not be
labelled overall account health.

## Threshold sensitivity

| Decline threshold | Minimum euro decline | Watch share of assessable high-value accounts |
|---:|---:|---:|
| 20% | EUR 10 | 27.87% |
| 30% | EUR 10 | **23.21%** |
| 40% | EUR 10 | 17.98% |

The signal stays material across the range, but the exact count depends on the
chosen policy threshold.

## Where the warning is concentrated

| Segment | Assessable high-value accounts | Watch | Watch rate | Observed monthly gap |
|---|---:|---:|---:|---:|
| BTP | 515 | 150 | 29.13% | EUR 13.87k |
| Automobile Trade Repair | 106 | 36 | 33.96% | EUR 3.68k |
| Retail | 249 | 61 | 24.50% | EUR 3.23k |
| Consultant | 357 | 60 | 16.81% | EUR 5.53k |
| Start | 1,033 | 242 | 23.43% | EUR 16.43k |
| Plus | 558 | 135 | 24.19% | EUR 13.19k |
| Free | 453 | 101 | 22.30% | EUR 8.14k |
| Business | 80 | 15 | 18.75% | EUR 3.19k |

BTP remains the largest growth opportunity, but it is also the largest absolute
early-warning pool. This strengthens the case for learning which product
behaviors drive BTP revenue rather than running a generic plan-upsell campaign.

## Recommended action

1. Use `Watch` as a diagnostic trigger: identify which revenue component fell
   and check operational or data issues before contacting a company.
2. Intervene after the first missing revenue month when the return probability
   is still highest; monitor recovered accounts separately.
3. Add product events—card transactions, balances, transfers, payments,
   invoicing, paid features, and engagement—to determine what caused the decline.
4. Validate the 30% and EUR 10 thresholds prospectively against future revenue,
   support outcomes, and normal volatility before production use.

Do not treat a revenue decline as churn, dissatisfaction, financial distress, or
a reason for an adverse eligibility decision.

## Supporting files

- `sql/presentation_kpis.sql`: production-style definitions and result tables.
- `sql/account_health_playground.sql`: editable threshold sensitivity.
- `outputs/eda/eda_company_revenue_momentum_at_cutoff.csv`: company-level audit.
- `outputs/eda/eda_top20_account_health_summary.csv`: revised high-value states.
- `outputs/eda/eda_revenue_momentum_threshold_sensitivity.csv`: threshold tests.
- `outputs/eda/eda_top20_revenue_momentum_by_segment.csv`: persona and plan mix.
