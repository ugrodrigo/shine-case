# Shine case: data inconsistencies and questions

## Summary

The files appear structurally sound:

- Company IDs are unique.
- Company-month revenue keys are unique.
- Every revenue company exists in the companies table.
- UUIDs and dates parse correctly.
- Revenue fields contain no missing values.

The main concerns are therefore not basic corruption, but coverage gaps and ambiguous business definitions that could materially affect conclusions about revenue, activity, retention, and churn.

## Questions to prioritize

### 1. What are the cohort and observation windows?

**Finding:** Signup data stops abruptly on 1 May 2026. All 247 May signups occurred on that date. However, validations, activations, and closures continue through 28–29 May, and May revenue is present. The files labelled “2026 YTD” also contain data from October–December 2025.

**Question:**

> What are the intended cohort and observation windows? Is May revenue complete, and were companies deliberately restricted to signups through 1 May? Should October–December 2025 be treated as historical context or included in the analysis period?

**Why it matters:** An incomplete May signup cohort or unclear cutoff would distort acquisition trends, conversion rates, cohort comparisons, and recent-customer maturity.

### 2. Does a missing revenue row mean zero revenue?

**Finding:** There are 19,370 activated companies, but only 19,305 appear in the revenue table. Sixty-five activated companies have no revenue record at all, including some activated as early as October 2025.

Under the assumption that every activated company should have one row per month until closure or the May cutoff:

- 1,383 companies are missing at least one expected revenue month.
- 3,132 expected company-month records are absent.
- 237 companies have 358 internal gaps—revenue records before and after a missing month.
- 1,113 companies stop appearing before closure or the end of the observation period.
- Every supplied revenue row contains positive deposit-interest revenue, suggesting the table may include only revenue-generating months rather than a complete monthly company spine.

**Question:**

> Does an absent company-month mean exactly €0 revenue, or can it indicate a pipeline omission or another account state? Should I construct zero-revenue rows for missing months?

**Why it matters:** This directly affects active-customer counts, ARPU, retention, revenue churn, and whether disappearance from the revenue table can be treated as inactivity.

### 3. What does `company_closed_date` mean?

**Finding:** Of 3,795 companies with a closure date, 2,551 were never activated and 1,803 were never validated. Conversely:

- 825 activated, unclosed companies have revenue but stop generating it before May.
- 44 activated, unclosed companies never generate revenue.
- 21 activated and closed companies never generate revenue.

**Question:**

> What exactly does `company_closed_date` represent: profile/application closure, bank-account closure, or subscription cancellation? Should pre-activation closures be treated as funnel loss rather than customer churn, and can an unclosed account be dormant or churned?

**Why it matters:** Closure cannot safely be used as the sole churn definition until its business meaning is established.

### 4. Is historical subscription-plan data available?

**Finding:** The company table contains only `initial_subscription_group`, not the current or effective-dated plan. Nevertheless:

- 395 initially free companies later have positive subscription revenue.
- 5,725 initially paid companies have at least one zero-subscription-revenue month.

**Question:**

> Is effective-dated plan or subscription-status history available? Without it, can these records be interpreted as upgrades, downgrades, trials, waivers, pauses, or subscription churn?

**Why it matters:** Initial plan should not be used as if it were the customer’s plan in every subsequent month.

### 5. Are negative banking fees legitimate adjustments?

**Finding:** There are 28 negative banking-fee records, totalling –€806.76, with a minimum value of –€200. These cause 21 company-months to have negative total revenue.

**Question:**

> Are negative banking fees legitimate refunds, chargebacks, or accounting corrections? Should revenue be reported net of these values?

**Why it matters:** Removing or converting these values without clarification would overstate revenue; retaining them may be correct if the table is intended to contain net recognized revenue.

### 6. Can the large deposit-interest account be validated?

**Finding:** Company `ead429ea-1eba-4792-9b26-fd974fafe6d4` generates approximately €23,669 of deposit-interest revenue over the available period, representing 2.79% of all deposit-interest revenue. It produces roughly €4.3k–€4.8k in several individual months.

**Question:**

> Can you confirm the units and calculation of deposit-interest revenue, and whether this large account is a genuine customer rather than a test, aggregation, or extraction anomaly?

**Why it matters:** The value may be a legitimate high-balance customer, but it is sufficiently influential to validate before using it in averages, segment comparisons, or recommendations.

### 7. What monetary precision and rounding should be used?

**Finding:** The exported amounts contain floating-point artifacts such as `10.392515999999944`. Subscription, interchange, interest, and even some banking-fee values contain many decimal places. For example, 164 banking-fee records contain more than two decimal places.

**Question:**

> What accounting precision and rounding convention should be used? Are these values reconciled source amounts, or derived floating-point calculations?

**Why it matters:** Monetary calculations should normally use a defined decimal precision, with rounding applied consistently at the appropriate stage.

### 8. How should mixed date granularity be handled?

**Finding:** `company_signup_at` is a UTC timestamp, whereas validation, activation, and closure are date-only fields. If the date-only values are interpreted as midnight UTC:

- 3,855 validations appear earlier than signup.
- 419 activations appear earlier than signup.
- 383 closures appear earlier than signup.

These apparent reversals occur on the same calendar day, so they are most likely caused by mixed granularity rather than genuinely impossible sequencing.

**Question:**

> Should event sequencing be evaluated only at calendar-day granularity, and which business timezone applies?

**Why it matters:** Naively comparing the timestamp fields could falsely label valid same-day journeys as data errors or produce negative conversion times.

## Lower-priority segmentation question

`Others` represents 21.66% of all companies. The taxonomy also includes potentially overlapping or mixed-language categories such as `Repair`, `Repair_Installation`, `BTP`, `Professeur`, and `Restauration`.

**Question:**

> How are personas assigned, are the categories mutually exclusive, and was the taxonomy stable throughout the observation period?

This should be clarified before making strong persona-level recommendations.

## If there is time for only three questions

Ask about:

1. The cohort and observation windows, especially the May cutoff.
2. Whether missing company-month revenue rows mean zero revenue.
3. The exact meaning of `company_closed_date`.

These three issues have the greatest potential to change the analysis. The negative banking fees and large deposit-interest account are the strongest record-level validation checks.
