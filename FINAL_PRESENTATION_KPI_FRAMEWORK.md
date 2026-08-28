# Final presentation KPI framework

## The question to answer

> Where is the biggest revenue risk or opportunity for Shine right now, and what
> should we do about it?

## Recommended answer

The biggest immediate opportunity is to **protect and replicate Shine's
high-value revenue behavior**, particularly among BTP and Plus companies. The
main risk is concentration in a relatively small, usage- and balance-driven
customer pool—not evidence of a broad current churn crisis.

Evidence:

- The highest-value 20% of equal-tenure companies generate **67.02%** of
  four-month revenue. The raw cumulative sensitivity is 73.93%.
- BTP represents **25.96%** of the equal-tenure top-20 pool and **29.54%** of its
  revenue.
- Plus and Business are respectively **2.17x** and **3.85x** overrepresented in
  the equal-tenure top 20%.
- Interchange and deposit interest make up **70.7%** of April revenue. In the raw
  cumulative top-20 analysis, this group generates 82.04% of interchange and
  80.24% of deposit-interest revenue.
- High-value-account health is currently strong: **95.08%** of cumulative top-20
  companies are Healthy under the strict unbroken-revenue-streak definition.
  Only 2.42% are At-risk and 1.96% are Churned proxy.
- A broken streak still matters after recovery: restarted companies remain
  active next month 78.66% of the time versus 97.32% for continuously active
  companies at observed ages 2-4.

The recommended action is therefore a targeted high-value growth and protection
program, not a broad untargeted churn campaign:

1. Protect the existing top-value population with a first-missing-revenue-month
   trigger and continued monitoring after reactivation.
2. Test deeper product adoption within large, high-potential segments—especially
   BTP and Plus—using card usage, balances, and relevant paid features as levers.
3. Measure incremental revenue and account health against a control group before
   scaling. Initial-plan associations do not prove that changing plans causes
   higher revenue.

## Ranked initiatives for next quarter

### 1. BTP adoption and monetization experiment

Position: run a controlled experiment designed to move suitable BTP companies
toward the product behaviors associated with higher revenue. Do not assume that
a plan upsell is the lever; first identify the relevant card, balance, payment,
or feature-adoption behavior with product data.

Why this ranks first:

- BTP is the largest scalable high-value persona: 25.96% of the equal-tenure
  top-20 population and 29.54% of its revenue.
- 472 of 1,642 comparable BTP companies are already in the top 20%, leaving
  1,170 outside it as a historical indication of the potential addressable pool.
- BTP + Plus is 2.33x represented in the high-value pool, while BTP + Start is
  its largest absolute combination. This suggests product behavior and initial
  proposition both matter, but does not establish which causes higher revenue.
- BTP account continuity is reasonably strong, so the experiment targets growth
  rather than trying to repair a broadly unhealthy segment.

Magnitude that can be stated:

- Equal-tenure BTP population: 1,642 companies.
- BTP companies in the top 20%: 472; outside it: 1,170.
- BTP contributes EUR 266.4k, or 29.54%, of equal-tenure top-20 revenue.

Magnitude that cannot yet be stated:

- Incremental revenue obtainable from an intervention.
- Cost, margin, payback, or return on investment.
- How many current BTP companies are eligible for a specific product action.

Those require current-plan and product-usage data, treatment cost, margin, and a
causal experiment.

### 2. First-gap protection for high-value companies

Position: when a previously revenue-active high-value company first misses a
month, trigger proactive support; keep recovered companies monitored for a fixed
period.

Why this ranks second:

- Return probability declines from 13.4% after one inactive month to 4.9% after
  three, so the first gap is the practical intervention window.
- A recovered company remains active next month only 78.66% of the time versus
  97.32% for a continuously active company.
- Protecting the pool matters because Healthy and Recovered top-20 companies
  generate approximately EUR 424.0k of April revenue.

Why it is second rather than first:

- Only 154 cumulative top-20 companies are currently inactive: 85 At-risk and
  69 Churned proxy.
- Their combined last-observed monthly revenue is EUR 19.24k, approximately 3%
  of April company revenue. This is an exposure proxy, not expected recoverable
  revenue.
- The currently eligible treatment population may be too small for a fast,
  well-powered top-20-only experiment. A phased rollout or a broader pre-defined
  high-value band may be necessary.

## Alternatives considered and rejected

| Alternative | Why it looks attractive | Why it is not a top-two recommendation now |
|---|---|---|
| Acquire more Business companies | Highest revenue per company and strongest high-value representation | Only 196 comparable age-three companies; 73.3% funnel dropout and weak continuity. No CAC, channel, KYB-reason, or current-plan data. |
| Broad funnel overhaul | 62.9% fixed-window signup-to-activation dropout appears large | Only 5.1% is observed pre-activation closure; the rest cannot be separated into rejection, delay, abandonment, or extraction effects. No channel cost or application-reason data. |
| Blanket churn campaign | Retention is intuitively important | The high-value pool is 95.08% Healthy, and current inactive high-value exposure is smaller than the growth pool. A targeted first-gap program is more proportionate. |
| Immediate plan-upsell campaign | Plus and Business are strongly associated with value | Only initial plan is available. Current plan, upgrades, eligibility, price exposure, and causal plan effects are unknown. |
| Bikers Drivers as the lead growth segment | It has the clearest material inactivity signal | It is underrepresented in the high-value pool and has weaker continuity. It is better suited to a diagnostic retention study than the lead revenue-growth bet. |

This ranking is based on observable scale, value concentration, account health,
and actionability—not on a fully sized euro business case, which the supplied
data cannot support.

## Presentation terminology: single source of truth

Use `company` or `revenue account`, not `customer`, because the dataset is keyed
by `company_profile_id` and does not establish a person-level customer entity.

| Term | Operational definition | What it does not mean |
|---|---|---|
| Revenue-active company | Has a revenue row in the observation month. There are no exactly-zero total-revenue rows through April, so row presence and non-zero revenue are equivalent in this extract. | It does not prove product usage, login activity, an open bank account, or subscription status. |
| Healthy revenue account | Revenue-active now and has generated revenue in every observed calendar month since activation. Compare this rate at equal customer age when ranking cohorts or segments. | It is not a measure of profitability, satisfaction, credit quality, or contractual health. |
| Recovered / monitor | Revenue-active now but has at least one earlier missing revenue month after activation. | Reactivation does not mean risk has fully normalized. |
| At-risk | Previously revenue-active, then absent for one or two consecutive months—approximately 30-60 days. | A missing month is not confirmed cancellation. |
| Churned proxy | Previously revenue-active, then absent for at least three consecutive months—approximately 90+ days. | It is not confirmed customer churn. Companies can still return, and `company_closed_date` is not used. |
| Never monetized | Activated but no revenue has been observed by the measurement month. | This is not churn because the company was never revenue-active. |

Why the thresholds are defensible:

- Return within the next two observable months is 13.4% after one inactive
  month, 8.1% after two, and 4.9% after three.
- The three-month boundary is therefore a practical low-return threshold, but it
  must remain labelled `Churned proxy` until a formal cancellation event exists.

The implemented source is `sql/presentation_kpis.sql`, and the company-level
audit table is `eda_outputs/eda_company_account_health_at_cutoff.csv`.

## KPI hierarchy for the case

### Tier 1: put these on the three slides

#### 1. Tenure-controlled high-value concentration

Formula:

> Revenue generated by the top 20% of companies ranked by cumulative revenue
> through age three / total revenue through age three.

Current result: **67.02%**.

Why use it: it sizes the opportunity without giving older cohorts an unfair
advantage. The raw cumulative 73.93% result belongs in the appendix.

#### 2. High-value account-health distribution

Among the 3,514 cumulative top-20 companies as of April:

| State | Companies | Share of top 20% | Share of top-20 historical revenue |
|---|---:|---:|---:|
| Healthy revenue account | 3,341 | 95.08% | 96.15% |
| Recovered / monitor | 19 | 0.54% | 0.28% |
| At-risk | 85 | 2.42% | 2.12% |
| Churned proxy | 69 | 1.96% | 1.45% |

The last observed monthly revenue of the 154 inactive high-value companies is
EUR 19.24k. Treat this only as an exposure proxy, not forecast lost revenue.

Why use it: it shows that concentration is a structural risk, but there is no
current high-value churn emergency. The action should combine protection with
growth.

#### 3. Segment opportunity and representation

Show both absolute size and representation index. Representation index equals:

> Segment share of top-20 companies / segment share of the eligible base.

Preferred equal-tenure results:

- BTP: 25.96% of high-value companies, 29.54% of high-value revenue, 1.44x
  represented.
- Plus: 30.69% of high-value companies versus 14.15% of the base, 2.17x.
- Business: only 8.31% of high-value companies but 3.85x represented; valuable
  and risky, but too small to be the only growth recommendation.
- BTP + Plus: 8.91% of the high-value pool, 10.02% of its revenue, 2.33x
  represented.

Why use it: concentration alone says how much value is concentrated; segment
representation says where to act.

#### 4. Growth quality

Use no more than two supporting numbers:

- April revenue: EUR 638.1k, +17.1% month on month.
- Revenue-generating companies: +18.4%, while revenue per revenue company fell
  1.1% to EUR 39.56.

Why use it: the latest growth was volume-led. This makes customer-level
monetization and retention more relevant than celebrating total growth alone.

### Tier 2: supporting or appendix KPIs

#### Revenue mix

April mix: 42.0% interchange, 28.7% deposit interest, 21.0% subscription, and
8.2% banking fees. This explains why transaction activity, balances, and macro
economics matter.

#### Fixed-age observed LTV

Use cumulative observed revenue per original activated cohort member at the
same age. Do not call it forecast LTV. At age three, later cohorts show lower
observed value despite broadly stable lifecycle-state shares, suggesting weaker
monetization intensity rather than obvious retention deterioration.

#### At-risk return curve

Use the declining return probability to justify intervention after the first
missing revenue month and the provisional 90-day Churned-proxy threshold.

#### Streak persistence

Use only as one supporting behavioral fact: active-after-restarting companies
have materially lower next-month persistence than continuously active companies.
A full streak chart is redundant because Active and continuously Active shares
differ by only about one percentage point at age three.

#### Funnel conversion

The fixed 30-day signup-to-activation dropout is 62.9%. Business is highest at
73.3%. This is relevant if the recommendation includes acquisition or onboarding,
but it should not dominate a revenue-retention story because rejection reasons,
channel spend, and application status are unavailable.

## Most relevant additional KPI to build next

### Monthly revenue bridge

Decompose each month's revenue change into:

- Revenue from newly monetized companies.
- Revenue from reactivated companies.
- Expansion among companies active in both months.
- Contraction among companies active in both months.
- Revenue lost from companies that disappear.

Why this is the highest-priority next analysis: total revenue growth and company
counts show that April was volume-led, but they do not quantify whether the
installed base is expanding or contracting. A revenue bridge directly connects
the business question to acquisition, monetization, retention, and expansion.

Do not label this NRR without confirming that revenue is recurring and defining
the eligible opening base. Call it `same-company revenue retention` or a
`revenue bridge`.

### Other useful next KPIs if more data becomes available

| KPI | Why it matters | Additional data required |
|---|---|---|
| Gross and net revenue retention | Separates loss from expansion in a recurring base | Recurring-revenue definition and complete historical periods |
| Product adoption depth | Identifies behaviors causing interchange, balances, and retention | Transactions, card usage, transfers, balances, logins, and feature use |
| Plan upgrade/downgrade conversion | Tests the upmarket opportunity | Effective-dated current-plan history and plan-change events |
| Revenue margin / contribution profit | Distinguishes high revenue from high economic value | Cost-to-serve, interchange costs, interest expense, support and risk costs |
| CAC, payback, and LTV:CAC | Determines whether acquisition should be scaled | Channel-level spend and attributable acquisition data |
| High-value account retention | Measures whether the top-value pool remains valuable over time | More mature cohorts and a stable high-value definition |
| Experiment incremental revenue | Validates the recommended action | Treatment/control assignment and post-treatment observation |

## What to leave out—and defend

- **True churn rate:** there is no confirmed cancellation event. Use Churned
  proxy and show the definition.
- **`company_closed_date` as churn:** many closures occur before activation and
  closure meaning is ambiguous.
- **Forecast LTV:** seven confirmed revenue months are insufficient. Use observed
  cumulative revenue at fixed cohort age.
- **ARR/MRR and NRR:** not all revenue is contractual or recurring, and current
  subscription history is missing.
- **CAC, payback, or ROI:** acquisition cost and campaign data are absent.
- **Profitability:** revenue is not margin; cost data are absent.
- **Plan-conversion claims:** only the initial subscription group is supplied.
- **May as headline evidence:** signup coverage is truncated and completeness is
  not confirmed.
- **Rankings of tiny personas:** show sample thresholds and avoid declaring a
  winner based on a few dozen companies.

Leaving these out demonstrates metric discipline rather than incomplete work.

## Lead recommendation: causal test design

### Hypothesis

A targeted BTP product-adoption intervention causes incremental recognized
revenue without worsening customer, operational, risk, or fairness outcomes.

### Eligibility

- Define eligibility before randomization using a fixed pre-period.
- Start with revenue-active BTP companies below a pre-defined high-value
  threshold and with sufficient observation history.
- Use current plan and actual product-usage eligibility once those fields are
  available; do not rely on initial plan as if it were current.
- Exclude companies already in another conflicting campaign.

### Assignment

- Randomize treatment versus business-as-usual control.
- Stratify by pre-period revenue, cohort age, current plan, and relevant usage so
  the skewed high-value tail is balanced.
- Freeze the eligibility and high-value definitions before reading outcomes.
- Analyze intention-to-treat; do not remove customers who ignore the treatment.

### Treatment

Choose one specific, customer-appropriate lever after validating product data,
for example guided adoption of card payments or operational-account features.
Avoid bundling several unrelated actions because a positive result would not
identify what worked.

### Primary metric

> Incremental mean total revenue per eligible company over a fixed 90-day window
> versus control.

Mean revenue is the economic estimand, but the distribution is highly skewed.
Report a bootstrap confidence interval plus median and winsorized sensitivity.
Use pre-period revenue for variance reduction where appropriate.

### Secondary metrics

- Incremental interchange, deposit-interest, subscription, and banking-fee
  revenue per eligible company.
- Healthy-account retention and movement into At-risk.
- Product-adoption conversion for the behavior actually targeted.
- Treatment reach and engagement.

### Guardrails

- Account closure, complaints, support contacts, and operational failures.
- Fraud, AML, credit, or other risk outcomes where relevant.
- Unequal treatment or outcomes across protected or sensitive populations.
- Negative-fee adjustments and unexpected accounting effects.

### Success criterion

Scale only if the pre-registered confidence interval supports positive
incremental revenue above the fully loaded intervention-cost hurdle, with no
material deterioration in guardrails. A numeric uplift threshold cannot be set
from the supplied data because treatment cost, margin, outcome variance for the
final eligible population, and leadership's economic hurdle are missing. Use
those inputs for the power calculation before launch.

### Association versus causation

The dataset shows that BTP and Plus are associated with higher revenue and
high-value representation. It does not prove that marketing to BTP, changing a
plan, or increasing a particular product behavior will cause revenue growth.
Random assignment is what establishes the causal effect of the chosen lever.

## Validate these three things before leadership acts

### 1. Missing revenue rows and extraction completeness

Confirm whether an absent company-month means zero recognized revenue, delayed
posting, or missing ingestion. Reconcile monthly totals to Finance and confirm
the extract's population coverage. Keep May outside headline metrics until its
truncated signup coverage is explained.

### 2. Business meaning and effective-dated attributes

Confirm the authoritative definitions of activation, closure, cancellation, and
revenue recognition. Obtain current/effective-dated plan history and validate
whether persona is stable through time. Do not use `company_closed_date` as
customer churn without business confirmation.

### 3. KYB provenance, privacy, and permitted use

Determine how persona was derived and whether KYB-sourced attributes may legally
and ethically be used for product targeting. Apply purpose limitation, data
minimization, access controls, retention rules, and small-cell suppression. Do
not use this analysis for credit, onboarding, or adverse eligibility decisions.
Risk, Compliance, and Privacy should approve the feature set and use case before
activation.

## Productionising trusted, repeatable metrics

### Modelling approach

1. Preserve immutable, access-controlled raw company and revenue snapshots.
2. Build typed staging models with explicit timezone, decimal, date, and null
   handling.
3. Maintain a company-month revenue fact at one row per
   `company_profile_id × revenue_month`.
4. Maintain effective-dated company dimensions for persona and subscription
   plan rather than relying only on initial values.
5. Build versioned marts for cohort age, revenue states, account health,
   concentration, and experiments.
6. Publish a governed semantic layer or metric catalog containing formula,
   denominator, cutoff, owner, refresh schedule, and known limitations.

### Automated tests

- Unique company-month key and unique company-profile key.
- Referential integrity between revenue and company dimensions.
- Revenue components reconcile exactly to total revenue and Finance control
  totals; decimals remain unrounded until presentation.
- Signup ≤ validation ≤ activation ordering checks, with exceptions surfaced.
- Freshness, month completeness, row-count, and distribution anomaly checks.
- State-transition invariants: Never monetized cannot become Churned proxy before
  first revenue; inactivity resets after revenue returns.
- Cohort denominators remain fixed across customer age.
- Backfill and late-arriving-data tests so historical metrics change only for a
  documented reason.

### Ownership

- Finance owns revenue recognition and reconciliation.
- Product/Growth owns the intervention, product-adoption definition, and action
  thresholds.
- Data owns models, tests, lineage, metric definitions, and monitoring.
- Risk/Compliance/Privacy owns approval of KYB-derived fields and customer use.
- Operations or CRM owns intervention execution and contact-quality monitoring.

Refresh after the monthly Finance close, version definition changes, retain an
audit trail, and alert owners when completeness or reconciliation tests fail.

## Recommended three-page structure

### Page 1 — Position and magnitude

Headline:

> The highest-value 20% generate 67% of equal-tenure revenue; BTP contributes
> 30% of that value and is the clearest scalable opportunity.

Use:

- Lead with `20% of companies → 67% of equal-tenure revenue`.
- Show BTP share and Plus/Business representation.
- Use April growth and the 71% usage/balance mix only as current context.
- State the position: protect and replicate the high-value pool.

### Page 2 — Ranked decisions and rejected alternatives

Headline:

> Rank 1: BTP adoption experiment. Rank 2: first-gap high-value protection.

Use:

- Put the two initiatives in a table with evidence, observable magnitude, and
  what cannot be sized.
- Show that 95% of high-value accounts are Healthy, which is why blanket churn
  is not the first recommendation.
- Name the rejected alternatives: Business acquisition, broad funnel overhaul,
  blanket churn, and immediate plan upsell.

### Page 3 — Prove the lever and make the metrics trustworthy

- Summarize the randomized BTP test, primary metric, guardrails, and success
  criterion.
- List the three validations: missing-row semantics/completeness, business
  definitions/effective-dated plan, and KYB/privacy permission.
- Add the production engine in one line: governed company-month fact → versioned
  metric marts → automated tests → named Finance, Product, Data, and Risk owners.
- Point to the SQL appendix rather than putting full queries on the page.

## Five-minute video structure

- **0:00-0:40 — Position:** answer the question immediately and define the
  confirmed April cutoff.
- **0:40-1:40 — Proof and magnitude:** concentration, BTP/Plus composition, and
  usage/balance revenue mix.
- **1:40-2:50 — Ranked initiatives:** explain why adoption is first, first-gap
  protection second, and why the alternatives lose.
- **2:50-4:00 — Causal test:** eligibility, randomization, primary metric,
  guardrails, and success threshold.
- **4:00-4:40 — What cannot be concluded:** no true churn, forecast LTV, causal
  plan effect, CAC, margin, or May completeness.
- **4:40-5:00 — Trust:** three validations plus production ownership.

## Files supporting the presentation

- `sql/presentation_kpis.sql`: formal account-health classification.
- `eda_outputs/eda_top20_account_health_summary.csv`: high-value health table.
- `eda_outputs/eda_account_health_by_segment.csv`: health by persona and plan.
- `REVENUE_CONCENTRATION_FINDINGS.md`: concentration and segment evidence.
- `COHORT_STATE_FINDINGS.md`: cohort lifecycle states.
- `STREAK_LOYALTY_FINDINGS.md`: streak and recovery evidence.
- `KPI_DEEP_DIVE_FINDINGS.md`: funnel, revenue, inactivity, LTV, and acquisition.
