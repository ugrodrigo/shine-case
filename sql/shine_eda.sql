-- Shine Senior Data Analyst case
-- Focused exploratory analysis in DuckDB SQL.
-- Run from the project root with: python run_eda.py

-- ============================================================
-- 1. LOAD AND TYPE THE SOURCE DATA
-- ============================================================
-- Loading as VARCHAR first avoids silent CSV type assumptions. TRY_CAST makes
-- malformed values visible as NULL instead of stopping the whole analysis.

CREATE OR REPLACE TABLE companies AS
SELECT
    company_profile_id,
    persona,
    initial_subscription_group,
    -- Every source value is explicitly labelled UTC. Keep the UTC wall-clock
    -- value as TIMESTAMP so month bucketing cannot shift at timezone boundaries.
    TRY_CAST(REPLACE(company_signup_at, ' UTC', '') AS TIMESTAMP)
        AS company_signup_at,
    TRY_CAST(account_validation_date AS DATE) AS validation_date,
    TRY_CAST(company_activation_date AS DATE) AS activation_date,
    TRY_CAST(company_closed_date AS DATE) AS closed_date
FROM read_csv(
    'dataset/companies-shine-table-2026-ytd-1-.csv',
    header = true,
    all_varchar = true
);

CREATE OR REPLACE TABLE revenue AS
SELECT
    TRY_CAST(revenue_month AS DATE) AS revenue_month,
    company_profile_id,
    -- The source contains up to 20 fractional digits. Preserve them through
    -- calculations and round only in presentation-level SELECT statements.
    TRY_CAST(subscription_revenue AS DECIMAL(38, 20))
        AS subscription_revenue,
    TRY_CAST(interchange_revenue AS DECIMAL(38, 20))
        AS interchange_revenue,
    TRY_CAST(banking_fees AS DECIMAL(38, 20))
        AS banking_fees,
    TRY_CAST(deposit_interest_revenue AS DECIMAL(38, 20))
        AS deposit_interest_revenue
FROM read_csv(
    'dataset/revenue-shine-table-2026-ytd-1-.csv',
    header = true,
    all_varchar = true
);

CREATE OR REPLACE VIEW revenue_with_total AS
SELECT
    *,
    subscription_revenue
        + interchange_revenue
        + banking_fees
        + deposit_interest_revenue AS total_revenue
FROM revenue;

-- ============================================================
-- 2. DATA-QUALITY SUMMARY
-- ============================================================

CREATE OR REPLACE TABLE eda_data_quality AS
SELECT 'company rows' AS metric, COUNT(*)::VARCHAR AS value
FROM companies

UNION ALL
SELECT 'revenue rows', COUNT(*)::VARCHAR
FROM revenue

UNION ALL
SELECT 'unique revenue companies', COUNT(DISTINCT company_profile_id)::VARCHAR
FROM revenue

UNION ALL
SELECT 'duplicate company IDs', COUNT(*)::VARCHAR
FROM (
    SELECT company_profile_id
    FROM companies
    GROUP BY company_profile_id
    HAVING COUNT(*) > 1
)

UNION ALL
SELECT 'duplicate company-month revenue keys', COUNT(*)::VARCHAR
FROM (
    SELECT company_profile_id, revenue_month
    FROM revenue
    GROUP BY company_profile_id, revenue_month
    HAVING COUNT(*) > 1
)

UNION ALL
SELECT 'revenue companies absent from companies', COUNT(DISTINCT r.company_profile_id)::VARCHAR
FROM revenue r
LEFT JOIN companies c USING (company_profile_id)
WHERE c.company_profile_id IS NULL

UNION ALL
SELECT 'validated companies', COUNT(*) FILTER (WHERE validation_date IS NOT NULL)::VARCHAR
FROM companies

UNION ALL
SELECT 'activated companies', COUNT(*) FILTER (WHERE activation_date IS NOT NULL)::VARCHAR
FROM companies

UNION ALL
SELECT 'closed companies', COUNT(*) FILTER (WHERE closed_date IS NOT NULL)::VARCHAR
FROM companies

UNION ALL
SELECT 'closed without activation', COUNT(*) FILTER (
    WHERE closed_date IS NOT NULL AND activation_date IS NULL
)::VARCHAR
FROM companies

UNION ALL
SELECT 'activated companies with no revenue row', COUNT(*)::VARCHAR
FROM companies c
LEFT JOIN revenue r USING (company_profile_id)
WHERE c.activation_date IS NOT NULL
  AND r.company_profile_id IS NULL

UNION ALL
SELECT 'negative banking-fee rows', COUNT(*) FILTER (WHERE banking_fees < 0)::VARCHAR
FROM revenue

UNION ALL
SELECT 'negative total-revenue rows', COUNT(*) FILTER (WHERE total_revenue < 0)::VARCHAR
FROM revenue_with_total

UNION ALL
SELECT 'first revenue month', MIN(revenue_month)::VARCHAR
FROM revenue

UNION ALL
SELECT 'last revenue month', MAX(revenue_month)::VARCHAR
FROM revenue

UNION ALL
SELECT 'first signup timestamp', MIN(company_signup_at)::VARCHAR
FROM companies

UNION ALL
SELECT 'last signup timestamp', MAX(company_signup_at)::VARCHAR
FROM companies;

-- ============================================================
-- 3. SIGNUP-COHORT FUNNEL
-- ============================================================
-- These are eventual conversion rates within the available observation window.
-- Recent cohorts are right-censored and should not be compared naively.

CREATE OR REPLACE TABLE eda_funnel_by_signup_month AS
SELECT
    DATE_TRUNC('month', company_signup_at)::DATE AS signup_month,
    COUNT(*) AS signups,
    COUNT(*) FILTER (WHERE validation_date IS NOT NULL) AS validated,
    COUNT(*) FILTER (WHERE activation_date IS NOT NULL) AS activated,
    COUNT(*) FILTER (WHERE closed_date IS NOT NULL) AS closed_profiles,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE validation_date IS NOT NULL)
        / NULLIF(COUNT(*), 0),
        1
    ) AS validation_rate_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE activation_date IS NOT NULL)
        / NULLIF(COUNT(*), 0),
        1
    ) AS activation_rate_pct
FROM companies
GROUP BY 1
ORDER BY 1;

-- ============================================================
-- 4. MONTHLY REVENUE AND REVENUE MIX
-- ============================================================
-- "Revenue companies" means companies present in the revenue table. It is not
-- called "active companies" because missing company-month semantics are unclear.

CREATE OR REPLACE TABLE eda_monthly_revenue AS
WITH monthly AS (
    SELECT
        revenue_month,
        COUNT(DISTINCT company_profile_id) AS revenue_companies,
        SUM(subscription_revenue) AS subscription_revenue,
        SUM(interchange_revenue) AS interchange_revenue,
        SUM(banking_fees) AS banking_fees,
        SUM(deposit_interest_revenue) AS deposit_interest_revenue,
        SUM(total_revenue) AS total_revenue
    FROM revenue_with_total
    GROUP BY revenue_month
),
with_growth AS (
    SELECT
        *,
        LAG(total_revenue) OVER (ORDER BY revenue_month) AS prior_month_revenue
    FROM monthly
)
SELECT
    revenue_month,
    revenue_companies,
    ROUND(subscription_revenue, 2) AS subscription_revenue,
    ROUND(interchange_revenue, 2) AS interchange_revenue,
    ROUND(banking_fees, 2) AS banking_fees,
    ROUND(deposit_interest_revenue, 2) AS deposit_interest_revenue,
    ROUND(total_revenue, 2) AS total_revenue,
    ROUND(total_revenue / NULLIF(revenue_companies, 0), 2)
        AS revenue_per_revenue_company,
    ROUND(
        100.0 * (total_revenue / NULLIF(prior_month_revenue, 0) - 1),
        1
    ) AS total_revenue_mom_growth_pct,
    ROUND(100.0 * subscription_revenue / NULLIF(total_revenue, 0), 1)
        AS subscription_share_pct,
    ROUND(100.0 * interchange_revenue / NULLIF(total_revenue, 0), 1)
        AS interchange_share_pct,
    ROUND(100.0 * banking_fees / NULLIF(total_revenue, 0), 1)
        AS banking_fees_share_pct,
    ROUND(100.0 * deposit_interest_revenue / NULLIF(total_revenue, 0), 1)
        AS deposit_interest_share_pct
FROM with_growth
ORDER BY revenue_month;

-- Long-form table convenient for a stacked revenue chart.
CREATE OR REPLACE TABLE eda_monthly_revenue_long AS
SELECT revenue_month, 'Subscription' AS revenue_stream,
       ROUND(SUM(subscription_revenue), 2) AS revenue
FROM revenue
GROUP BY revenue_month
UNION ALL
SELECT revenue_month, 'Interchange', ROUND(SUM(interchange_revenue), 2)
FROM revenue
GROUP BY revenue_month
UNION ALL
SELECT revenue_month, 'Banking fees', ROUND(SUM(banking_fees), 2)
FROM revenue
GROUP BY revenue_month
UNION ALL
SELECT revenue_month, 'Deposit interest', ROUND(SUM(deposit_interest_revenue), 2)
FROM revenue
GROUP BY revenue_month
ORDER BY revenue_month, revenue_stream;

-- ============================================================
-- 5. MAY REVENUE BY PERSONA AND INITIAL PLAN
-- ============================================================
-- May is used as the latest supplied revenue month. "Initial plan" must not be
-- interpreted as the plan held in May.

CREATE OR REPLACE TABLE eda_may_revenue_by_persona AS
WITH may_company AS (
    SELECT
        c.persona,
        r.company_profile_id,
        SUM(r.subscription_revenue) AS subscription_revenue,
        SUM(r.interchange_revenue) AS interchange_revenue,
        SUM(r.banking_fees) AS banking_fees,
        SUM(r.deposit_interest_revenue) AS deposit_interest_revenue,
        SUM(r.total_revenue) AS total_revenue
    FROM revenue_with_total r
    JOIN companies c USING (company_profile_id)
    WHERE r.revenue_month = DATE '2026-05-01'
    GROUP BY c.persona, r.company_profile_id
),
persona AS (
    SELECT
        persona,
        COUNT(*) AS revenue_companies,
        SUM(subscription_revenue) AS subscription_revenue,
        SUM(interchange_revenue) AS interchange_revenue,
        SUM(banking_fees) AS banking_fees,
        SUM(deposit_interest_revenue) AS deposit_interest_revenue,
        SUM(total_revenue) AS total_revenue,
        AVG(total_revenue) AS average_revenue_per_company,
        MEDIAN(total_revenue) AS median_revenue_per_company
    FROM may_company
    GROUP BY persona
)
SELECT
    persona,
    revenue_companies,
    ROUND(subscription_revenue, 2) AS subscription_revenue,
    ROUND(interchange_revenue, 2) AS interchange_revenue,
    ROUND(banking_fees, 2) AS banking_fees,
    ROUND(deposit_interest_revenue, 2) AS deposit_interest_revenue,
    ROUND(total_revenue, 2) AS total_revenue,
    ROUND(average_revenue_per_company, 2) AS average_revenue_per_company,
    ROUND(median_revenue_per_company, 2) AS median_revenue_per_company,
    ROUND(100.0 * total_revenue / SUM(total_revenue) OVER (), 1)
        AS total_revenue_share_pct
FROM persona
ORDER BY total_revenue DESC;

CREATE OR REPLACE TABLE eda_may_revenue_by_initial_plan AS
WITH may_company AS (
    SELECT
        c.initial_subscription_group,
        r.company_profile_id,
        SUM(r.subscription_revenue) AS subscription_revenue,
        SUM(r.interchange_revenue) AS interchange_revenue,
        SUM(r.banking_fees) AS banking_fees,
        SUM(r.deposit_interest_revenue) AS deposit_interest_revenue,
        SUM(r.total_revenue) AS total_revenue
    FROM revenue_with_total r
    JOIN companies c USING (company_profile_id)
    WHERE r.revenue_month = DATE '2026-05-01'
    GROUP BY c.initial_subscription_group, r.company_profile_id
)
SELECT
    initial_subscription_group,
    COUNT(*) AS revenue_companies,
    ROUND(SUM(subscription_revenue), 2) AS subscription_revenue,
    ROUND(SUM(interchange_revenue), 2) AS interchange_revenue,
    ROUND(SUM(banking_fees), 2) AS banking_fees,
    ROUND(SUM(deposit_interest_revenue), 2) AS deposit_interest_revenue,
    ROUND(SUM(total_revenue), 2) AS total_revenue,
    ROUND(AVG(total_revenue), 2) AS average_revenue_per_company,
    ROUND(MEDIAN(total_revenue), 2) AS median_revenue_per_company,
    ROUND(100.0 * SUM(total_revenue) / SUM(SUM(total_revenue)) OVER (), 1)
        AS total_revenue_share_pct
FROM may_company
GROUP BY initial_subscription_group
ORDER BY total_revenue DESC;

-- ============================================================
-- 6. ACTIVATION COHORTS
-- ============================================================
-- This shows revenue among companies that appear in the revenue table. Missing
-- rows are not filled with zero until their meaning is confirmed.

CREATE OR REPLACE TABLE eda_activation_cohorts AS
WITH company_month AS (
    SELECT
        DATE_TRUNC('month', c.activation_date)::DATE AS activation_month,
        r.revenue_month,
        DATE_DIFF(
            'month',
            DATE_TRUNC('month', c.activation_date),
            r.revenue_month
        ) AS months_since_activation,
        r.company_profile_id,
        r.total_revenue
    FROM revenue_with_total r
    JOIN companies c USING (company_profile_id)
    WHERE c.activation_date IS NOT NULL
)
SELECT
    activation_month,
    revenue_month,
    months_since_activation,
    COUNT(DISTINCT company_profile_id) AS revenue_companies,
    ROUND(SUM(total_revenue), 2) AS total_revenue,
    ROUND(SUM(total_revenue) / COUNT(DISTINCT company_profile_id), 2)
        AS revenue_per_revenue_company
FROM company_month
GROUP BY activation_month, revenue_month, months_since_activation
ORDER BY activation_month, revenue_month;

-- ============================================================
-- 7. EXPECTED LIFECYCLE MONTHS MISSING FROM REVENUE
-- ============================================================
-- ASSUMPTION FOR THIS DIAGNOSTIC ONLY:
-- Every activated company is expected to have a row from activation month
-- through closure month or May 2026, whichever comes first. This is a question
-- to validate, not a rule imposed on the final business metrics.

CREATE OR REPLACE TABLE eda_missing_revenue_months AS
WITH lifecycle AS (
    SELECT
        company_profile_id,
        DATE_TRUNC('month', activation_date)::DATE AS activation_month,
        LEAST(
            COALESCE(DATE_TRUNC('month', closed_date)::DATE, DATE '2026-05-01'),
            DATE '2026-05-01'
        ) AS end_month
    FROM companies
    WHERE activation_date IS NOT NULL
),
expected AS (
    SELECT
        l.company_profile_id,
        gs.expected_month::DATE AS expected_month
    FROM lifecycle l,
    LATERAL GENERATE_SERIES(
        l.activation_month,
        l.end_month,
        INTERVAL '1 month'
    ) AS gs(expected_month)
),
observed_span AS (
    SELECT
        company_profile_id,
        MIN(revenue_month) AS first_observed_month,
        MAX(revenue_month) AS last_observed_month
    FROM revenue
    GROUP BY company_profile_id
),
missing AS (
    SELECT
        e.company_profile_id,
        e.expected_month,
        s.first_observed_month,
        s.last_observed_month,
        CASE
            WHEN s.company_profile_id IS NULL THEN 'no revenue ever'
            WHEN e.expected_month < s.first_observed_month THEN 'before first observed'
            WHEN e.expected_month > s.last_observed_month THEN 'after last observed'
            ELSE 'internal gap'
        END AS gap_type
    FROM expected e
    LEFT JOIN revenue r
        ON e.company_profile_id = r.company_profile_id
       AND e.expected_month = r.revenue_month
    LEFT JOIN observed_span s
        ON e.company_profile_id = s.company_profile_id
    WHERE r.company_profile_id IS NULL
)
SELECT *
FROM missing
ORDER BY expected_month, company_profile_id;

CREATE OR REPLACE TABLE eda_missing_revenue_summary AS
SELECT
    gap_type,
    COUNT(*) AS missing_company_months,
    COUNT(DISTINCT company_profile_id) AS affected_companies
FROM eda_missing_revenue_months
GROUP BY gap_type
ORDER BY missing_company_months DESC;

-- ============================================================
-- 8. OUTLIERS, CONCENTRATION, AND NEGATIVE FEES
-- ============================================================

CREATE OR REPLACE TABLE eda_top_companies AS
WITH company_revenue AS (
    SELECT
        company_profile_id,
        COUNT(*) AS revenue_months,
        SUM(subscription_revenue) AS subscription_revenue,
        SUM(interchange_revenue) AS interchange_revenue,
        SUM(banking_fees) AS banking_fees,
        SUM(deposit_interest_revenue) AS deposit_interest_revenue,
        SUM(total_revenue) AS total_revenue
    FROM revenue_with_total
    GROUP BY company_profile_id
)
SELECT
    cr.*,
    c.persona,
    c.initial_subscription_group,
    c.activation_date,
    c.closed_date,
    ROUND(100.0 * cr.total_revenue / SUM(cr.total_revenue) OVER (), 2)
        AS all_revenue_share_pct
FROM company_revenue cr
JOIN companies c USING (company_profile_id)
ORDER BY total_revenue DESC
LIMIT 25;

CREATE OR REPLACE TABLE eda_component_concentration AS
WITH company_components AS (
    SELECT
        company_profile_id,
        SUM(subscription_revenue) AS subscription,
        SUM(interchange_revenue) AS interchange,
        SUM(banking_fees) AS banking_fees,
        SUM(deposit_interest_revenue) AS deposit_interest,
        SUM(total_revenue) AS total
    FROM revenue_with_total
    GROUP BY company_profile_id
),
long_form AS (
    SELECT company_profile_id, 'Subscription' AS component, subscription AS amount
    FROM company_components
    UNION ALL
    SELECT company_profile_id, 'Interchange', interchange FROM company_components
    UNION ALL
    SELECT company_profile_id, 'Banking fees', banking_fees FROM company_components
    UNION ALL
    SELECT company_profile_id, 'Deposit interest', deposit_interest FROM company_components
    UNION ALL
    SELECT company_profile_id, 'Total revenue', total FROM company_components
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY component ORDER BY amount DESC) AS value_rank
    FROM long_form
)
SELECT
    component,
    ROUND(SUM(amount), 2) AS component_revenue,
    ROUND(MAX(amount) FILTER (WHERE value_rank = 1), 2) AS top_company_revenue,
    ROUND(
        100.0 * MAX(amount) FILTER (WHERE value_rank = 1)
        / NULLIF(SUM(amount), 0),
        2
    ) AS top_company_share_pct,
    ROUND(
        100.0 * SUM(amount) FILTER (WHERE value_rank <= 10)
        / NULLIF(SUM(amount), 0),
        2
    ) AS top_10_companies_share_pct
FROM ranked
GROUP BY component
ORDER BY component_revenue DESC;

CREATE OR REPLACE TABLE eda_negative_banking_fees AS
SELECT
    r.revenue_month,
    r.company_profile_id,
    c.persona,
    c.initial_subscription_group,
    r.subscription_revenue,
    r.interchange_revenue,
    r.banking_fees,
    r.deposit_interest_revenue,
    r.total_revenue
FROM revenue_with_total r
JOIN companies c USING (company_profile_id)
WHERE r.banking_fees < 0
ORDER BY r.banking_fees;
