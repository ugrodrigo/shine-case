# Shine case: focused EDA findings

## Analytical cutoff

The core analysis stops at **April 2026**. May is retained only as a provisional
completeness check because all 247 May signups occur on 1 May, even though
revenue and later lifecycle events are present throughout the month.

The SQL therefore treats:

- January–April 2026 as the headline reporting period.
- October–December 2025 as cohort history and maturation context.
- May 2026 as a sensitivity check, not headline evidence.

## Executive read

Revenue is growing, but April growth was driven slightly more by the number of
revenue-generating companies than by monetization per company. The revenue mix
is also mostly dependent on balances and usage rather than subscriptions.

That suggests both a risk and an opportunity:

- **Risk:** growth may weaken if acquisition slows, card usage falls, balances
  move elsewhere, or interest economics change.
- **Opportunity to test:** improve early product adoption and move suitable
  customers toward higher-value paid propositions. The plan data is only the
  initial plan, so observed plan differences are associations rather than causal
  upgrade estimates.

## 1. April growth was volume-led

- April revenue was €638.1k, up 17.1% from March.
- Revenue-generating companies increased by 18.4%.
- Revenue per revenue-generating company fell by 1.1%, from €40.01 to €39.56.
- The latest confirmed revenue increase was therefore explained by company
  volume while monetization per observed company moved slightly backwards.

The very high growth earlier in the dataset should not be presented as mature
company-wide growth. The source begins with October 2025 signups, so each month
adds more acquisition cohorts to the observed population.

Important wording: these are **revenue-generating companies**, not necessarily
all active customers, because the meaning of an absent revenue row is unclear.

## 2. Most April revenue was non-subscription revenue

| Revenue stream | April revenue | Share |
|---|---:|---:|
| Interchange | €267.9k | 42.0% |
| Deposit interest | €183.4k | 28.7% |
| Subscription | €134.2k | 21.0% |
| Banking fees | €52.5k | 8.2% |

Interchange and deposit interest together contributed 70.7% of April revenue.
Only 21.0% came from subscriptions. This is not inherently unhealthy, but it
makes the revenue engine sensitive to customer transaction activity, deposited
balances, interchange economics, and interest-rate conditions.

The provisional May mix is very similar, so this conclusion does not depend on
May being complete. May should nevertheless remain outside the headline chart
until its extraction window is confirmed.

## 3. Cohorts monetize more after activation, then show an early plateau

Revenue per revenue-generating company generally rises during the first months
after activation:

- The October activation cohort rises from €29.84 in month 0 to approximately
  €52.5 in months 4–5, then falls to €50.77 in month 6.
- The November cohort rises from €30.64 in month 0 to €54.17 in month 4, then
  falls to €50.90 in month 5.

This suggests an early customer ramp-up followed by a possible plateau. It is
not yet proof of lifecycle decay: only the oldest cohorts are observable at
later ages, and missing revenue months may create selection bias.

## 4. Higher initial plans are associated with substantially higher value

April results by **initial** subscription group:

| Initial plan | Revenue companies | April revenue | Average/company | Median/company |
|---|---:|---:|---:|---:|
| Start | 7,316 | €287.3k | €39.27 | €15.62 |
| Plus | 2,027 | €168.8k | €83.28 | €38.16 |
| Free | 6,525 | €138.6k | €21.25 | €3.43 |
| Business | 262 | €43.3k | €165.31 | €85.20 |

Plus and Business together represented 14.2% of April revenue-generating
companies but 33.3% of April revenue. This makes upmarket adoption a promising
area to investigate.

However, the dataset contains only the initial plan. These results could reflect
customer selection, later upgrades or downgrades, or different customer
profiles. They do not show that changing a customer’s plan would cause the
observed revenue difference.

## 5. BTP is the largest April persona, but averages are skewed

- BTP generated €153.5k, or 24.1% of April revenue, from 2,895 companies.
- Average revenue was €53.02 per company, compared with a €19.04 median.
- The average-versus-median difference means a relatively small number of
  valuable accounts influence the average.

BTP may therefore be useful for a targeted experiment, but its distribution and
persona definition should be validated before generalizing.

## 6. Main data limitations through April

- Under an activation-to-closure/April lifecycle assumption, 1,081 companies
  are affected by 2,184 missing expected revenue months.
- This includes 237 companies with 358 internal gaps and 54 activated companies
  with no revenue through April.
- Of 3,795 profiles with a closure date in the supplied data, 2,551 were never
  activated, so closure cannot yet be equated with customer churn.
- Through April, there are 25 negative banking-fee records and 18 negative-total
  company-months. These may be legitimate accounting adjustments.
- Deposit-interest revenue is more concentrated than the other components: its
  top ten companies generate 10.10% of the component. Overall concentration is
  still modest, with the top ten companies generating 3.41% of revenue through
  April.

## May sensitivity check

May contains 17,433 revenue rows and €668.6k of recorded revenue. Validations,
activations, and closures continue through 28–29 May. This makes full-month
revenue plausible, but only 247 signups are supplied and all occur on 1 May.

Until the extraction logic is confirmed, May should be shown only as:

> Provisional sensitivity: revenue appears plausible, but signup coverage is
> truncated and full-month completeness has not been confirmed.

## Possible three-slide storyline

### Slide 1 — Growth is healthy but increasingly volume-dependent

Use the confirmed portion of `eda_monthly_revenue.csv`, ending in April. Add the
April callout: revenue +17.1%, revenue-generating companies +18.4%, and revenue
per company -1.1% versus March.

### Slide 2 — The engine is mostly usage- and balance-driven

Show the April mix and the cohort monetization curve. State the risk from
reliance on interchange and deposit interest, while acknowledging that customers
tend to ramp during their first months.

### Slide 3 — Test deeper adoption and upmarket conversion

Use the initial-plan and BTP results as targeting evidence, not causal proof.
Propose a controlled experiment measuring incremental revenue, retention,
product usage, and adverse outcomes. Include the missing-month, current-plan,
closure-definition, and May-cutoff checks as prerequisites before final sizing.
