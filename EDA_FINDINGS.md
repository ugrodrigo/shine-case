# Shine case: focused EDA findings

These findings are generated from `sql/shine_eda.sql`. The latest supplied
revenue month is May 2026.

## Executive read

Revenue is growing, but the latest growth is slowing and is being driven more
by the number of revenue-generating companies than by revenue per company.
The May revenue mix is also mostly dependent on customer balances and usage,
not recurring subscriptions.

That suggests both a risk and an opportunity:

- **Risk:** growth may weaken if acquisition slows, card usage falls, balances
  move elsewhere, or interest economics change.
- **Opportunity to test:** improve early product adoption and move suitable
  customers toward higher-value paid propositions. The plan data is only the
  initial plan, so the apparent plan differences are associations, not causal
  upgrade estimates.

## 1. Growth is slowing and the latest increase is volume-led

- Total monthly revenue rises from €35.6k in October 2025 to €668.6k in May
  2026. The early growth is strongly affected by the rapid accumulation of new
  cohorts and should not be presented as a mature steady-state growth rate.
- Month-on-month growth falls from 46.1% in February to 16.9% in March, 17.1%
  in April, and 4.8% in May.
- From April to May, revenue-generating companies increase by 8.1%, but revenue
  per revenue-generating company falls by 3.1%, from €39.56 to €38.35.
- Therefore, the latest total-revenue increase is explained by company volume;
  monetization per observed company moved in the opposite direction.

Important wording: these are **revenue-generating companies**, not necessarily
all active customers, because the meaning of an absent revenue row is unclear.

## 2. Most May revenue is non-subscription revenue

May revenue composition:

| Revenue stream | May revenue | Share |
|---|---:|---:|
| Interchange | €280.6k | 42.0% |
| Deposit interest | €195.5k | 29.2% |
| Subscription | €145.1k | 21.7% |
| Banking fees | €47.4k | 7.1% |

Interchange and deposit interest together contribute 71.2% of May revenue.
Only 21.7% comes from subscriptions. This is not inherently unhealthy, but it
makes the revenue engine sensitive to customer transaction activity, deposited
balances, interchange economics, and interest-rate conditions.

The April-to-May revenue increase of €30.5k consists of:

- +€12.7k interchange
- +€12.1k deposit interest
- +€10.8k subscriptions
- -€5.2k banking fees

## 3. Cohorts monetize more after activation, then show early signs of a plateau

Revenue per revenue-generating company generally rises during the first months
after activation:

- The October activation cohort rises from €29.84 in month 0 to approximately
  €52.5 in months 4–5, then falls to €48.01 by month 7.
- The November cohort rises from €30.64 in month 0 to €54.17 in month 4, then
  falls to €48.53 by month 6.

This suggests an early customer ramp-up period followed by a possible plateau
or decline. It is not yet proof of lifecycle decay: only the oldest cohorts are
observable at later ages, and missing revenue months may create selection bias.

## 4. Higher initial plans are associated with substantially higher value

May results by **initial** subscription group:

| Initial plan | Revenue companies | May revenue | Average/company | Median/company |
|---|---:|---:|---:|---:|
| Start | 7,934 | €306.2k | €38.60 | €15.51 |
| Plus | 2,113 | €173.4k | €82.04 | €38.76 |
| Free | 7,114 | €144.4k | €20.29 | €3.80 |
| Business | 272 | €44.6k | €164.09 | €85.09 |

Plus and Business together represent 13.7% of May revenue-generating companies
but 32.6% of May revenue. This makes upmarket adoption a promising area to
investigate.

However, the data contains only the initial plan. These results could reflect
customer selection, later upgrades/downgrades, or different customer profiles.
They do not show that changing a customer’s plan would cause the observed
revenue uplift.

## 5. BTP is the largest May persona, but averages are skewed

- BTP produces €163.8k, or 24.5% of May revenue, from 3,148 companies.
- Its average revenue is €52.04 per company, compared with a median of €20.40.
- The large average-versus-median difference means a relatively small number of
  valuable accounts influence the average.

BTP may therefore be a useful segment for a targeted experiment, but the
distribution and persona definition should be checked before generalizing.

## 6. The main data limitations remain decision-critical

- Sixty-five activated companies never appear in revenue.
- Under an activation-to-closure/May lifecycle assumption, 1,383 companies are
  missing at least one expected revenue month. This includes 237 companies with
  internal gaps.
- Of 3,795 closed profiles, 2,551 were never activated, so closure cannot yet be
  equated with customer churn.
- There are 28 negative banking-fee records and 21 negative-total-revenue
  company-months. These may be legitimate accounting adjustments.
- One company produces 2.79% of all deposit-interest revenue. Overall revenue
  concentration is nevertheless modest: the top ten companies produce 3.03%
  of total revenue.

## Possible three-slide storyline

### Slide 1 — Revenue growth is healthy but becoming acquisition-dependent

Use `eda_monthly_revenue.csv` for a stacked monthly revenue chart. Add the May
callout: revenue +4.8%, revenue-generating companies +8.1%, revenue/company
-3.1% versus April.

### Slide 2 — The engine is mostly usage- and balance-driven

Show the May mix and the cohort monetization curve. State the risk from reliance
on interchange and deposit interest, while acknowledging that customers tend to
ramp during their first months.

### Slide 3 — Test deeper adoption and upmarket conversion

Use the initial-plan and BTP results as targeting evidence, not causal proof.
Propose a controlled experiment measuring incremental revenue, retention,
product usage, and adverse outcomes. Include the missing-month, current-plan,
and closure-definition checks as prerequisites before final sizing.

