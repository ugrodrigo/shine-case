-- Shine case: requested KPI deep dive
-- This script runs after sql/shine_eda.sql and uses its typed source tables.
-- Core analysis ends at analysis_parameters.confirmed_end_month (April 2026).

-- ============================================================
-- 1. NEW-COMPANY TRENDS
-- ============================================================
-- "New company" means a new company profile/signup, not an activated account.
-- May is excluded because only 1 May is present in the signup source.

CREATE OR REPLACE TABLE eda_new_companies_by_month_segment AS
WITH aggregated AS (
    SELECT
        DATE_TRUNC('month', company_signup_at)::DATE AS signup_month,
        CASE WHEN GROUPING(persona) = 1 THEN 'ALL' ELSE persona END AS persona,
        CASE
            WHEN GROUPING(initial_subscription_group) = 1 THEN 'ALL'
            ELSE initial_subscription_group
        END AS initial_subscription_group,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1 THEN 'overall'
            WHEN GROUPING(persona) = 0
             AND GROUPING(initial_subscription_group) = 1 THEN 'persona'
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 0 THEN 'initial_plan'
            ELSE 'persona_x_initial_plan'
        END AS segment_level,
        COUNT(*) AS new_companies
    FROM companies
    WHERE company_signup_at::DATE
          < (SELECT provisional_month FROM analysis_parameters)
    GROUP BY GROUPING SETS (
        (DATE_TRUNC('month', company_signup_at)),
        (DATE_TRUNC('month', company_signup_at), persona),
        (DATE_TRUNC('month', company_signup_at), initial_subscription_group),
        (
            DATE_TRUNC('month', company_signup_at),
            persona,
            initial_subscription_group
        )
    )
)
SELECT *
FROM aggregated
ORDER BY signup_month, segment_level, persona, initial_subscription_group;

-- ============================================================
-- 2. THIRTY-DAY FUNNEL, DROPOUT, AND PRE-ACTIVATION CLOSURE
-- ============================================================
-- A fixed 30-day outcome window makes signup cohorts comparable and prevents
-- April signups from looking worse simply because they have less observation.
-- Eligible signups therefore end 30 days before the April observation date.
--
-- Definitions:
--   validation dropout = not validated within 30 days of signup
--   activation dropout = validated within 30 days but not activated within
--                        30 days of signup
--   total funnel dropout = not activated within 30 days of signup
--   pre-activation closure = closed within 30 days and never activated
--
-- Pre-activation closure is a data label, not proof of KYB rejection. It may
-- also contain abandonment or operational closure.

CREATE OR REPLACE TABLE eda_funnel_30d_by_signup_month_segment AS
WITH cutoff AS (
    SELECT
        (
            confirmed_end_month
            + INTERVAL '1 month'
            - INTERVAL '1 day'
        )::DATE AS observation_end_date
    FROM analysis_parameters
),
eligible AS (
    SELECT
        DATE_TRUNC('month', c.company_signup_at)::DATE AS signup_month,
        c.company_signup_at::DATE AS signup_date,
        c.persona,
        c.initial_subscription_group,
        c.validation_date,
        c.activation_date,
        c.closed_date,
        c.validation_date IS NOT NULL
            AND c.validation_date <= c.company_signup_at::DATE + 30
            AS validated_within_30d,
        c.activation_date IS NOT NULL
            AND c.activation_date <= c.company_signup_at::DATE + 30
            AS activated_within_30d,
        c.closed_date IS NOT NULL
            AND c.closed_date <= c.company_signup_at::DATE + 30
            AND c.activation_date IS NULL
            AS pre_activation_closed_within_30d
    FROM companies c
    CROSS JOIN cutoff x
    WHERE c.company_signup_at::DATE <= x.observation_end_date - 30
),
aggregated AS (
    SELECT
        signup_month,
        CASE WHEN GROUPING(persona) = 1 THEN 'ALL' ELSE persona END AS persona,
        CASE
            WHEN GROUPING(initial_subscription_group) = 1 THEN 'ALL'
            ELSE initial_subscription_group
        END AS initial_subscription_group,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1 THEN 'overall'
            WHEN GROUPING(persona) = 0
             AND GROUPING(initial_subscription_group) = 1 THEN 'persona'
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 0 THEN 'initial_plan'
            ELSE 'persona_x_initial_plan'
        END AS segment_level,
        COUNT(*) AS eligible_signups,
        COUNT(*) FILTER (WHERE validated_within_30d) AS validated_within_30d,
        COUNT(*) FILTER (WHERE activated_within_30d) AS activated_within_30d,
        COUNT(*) FILTER (WHERE pre_activation_closed_within_30d)
            AS pre_activation_closed_within_30d
    FROM eligible
    GROUP BY GROUPING SETS (
        (signup_month),
        (signup_month, persona),
        (signup_month, initial_subscription_group),
        (signup_month, persona, initial_subscription_group)
    )
)
SELECT
    *,
    ROUND(
        100.0 * (eligible_signups - validated_within_30d)
        / NULLIF(eligible_signups, 0),
        1
    ) AS signup_to_validation_dropout_pct,
    ROUND(
        100.0 * (validated_within_30d - activated_within_30d)
        / NULLIF(validated_within_30d, 0),
        1
    ) AS validation_to_activation_dropout_pct,
    ROUND(
        100.0 * (eligible_signups - activated_within_30d)
        / NULLIF(eligible_signups, 0),
        1
    ) AS total_signup_to_activation_dropout_pct,
    ROUND(
        100.0 * pre_activation_closed_within_30d
        / NULLIF(eligible_signups, 0),
        1
    ) AS pre_activation_closure_rate_pct
FROM aggregated
ORDER BY signup_month, segment_level, persona, initial_subscription_group;

-- ============================================================
-- 3. MONTHLY LOGO CHURN
-- ============================================================
-- Numerator: previously activated companies closing during the month.
-- Denominator: activated, unclosed companies at the start of the month.
-- Same-month activations and closures are reported separately because they are
-- not part of a conventional start-of-month churn denominator.

CREATE OR REPLACE TABLE eda_churn_monthly_by_segment AS
WITH months AS (
    SELECT gs.month_start::DATE AS month_start
    FROM analysis_parameters p,
    LATERAL GENERATE_SERIES(
        DATE '2025-10-01',
        p.confirmed_end_month,
        INTERVAL '1 month'
    ) AS gs(month_start)
),
company_month AS (
    SELECT
        m.month_start,
        c.company_profile_id,
        c.persona,
        c.initial_subscription_group,
        c.activation_date,
        c.closed_date
    FROM months m
    CROSS JOIN companies c
    WHERE c.activation_date IS NOT NULL
      AND c.activation_date
          < m.month_start + INTERVAL '1 month'
),
aggregated AS (
    SELECT
        month_start,
        CASE WHEN GROUPING(persona) = 1 THEN 'ALL' ELSE persona END AS persona,
        CASE
            WHEN GROUPING(initial_subscription_group) = 1 THEN 'ALL'
            ELSE initial_subscription_group
        END AS initial_subscription_group,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1 THEN 'overall'
            WHEN GROUPING(persona) = 0
             AND GROUPING(initial_subscription_group) = 1 THEN 'persona'
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 0 THEN 'initial_plan'
            ELSE 'persona_x_initial_plan'
        END AS segment_level,
        COUNT(*) FILTER (
            WHERE activation_date < month_start
              AND (closed_date IS NULL OR closed_date >= month_start)
        ) AS active_at_start,
        COUNT(*) FILTER (
            WHERE activation_date < month_start
              AND closed_date >= month_start
              AND closed_date < month_start + INTERVAL '1 month'
        ) AS churned_during_month,
        COUNT(*) FILTER (
            WHERE activation_date >= month_start
              AND activation_date < month_start + INTERVAL '1 month'
        ) AS activated_during_month,
        COUNT(*) FILTER (
            WHERE activation_date >= month_start
              AND activation_date < month_start + INTERVAL '1 month'
              AND closed_date >= activation_date
              AND closed_date < month_start + INTERVAL '1 month'
        ) AS activated_and_closed_same_month,
        COUNT(*) FILTER (
            WHERE activation_date < month_start + INTERVAL '1 month'
              AND (
                  closed_date IS NULL
                  OR closed_date >= month_start + INTERVAL '1 month'
              )
        ) AS active_at_end
    FROM company_month
    GROUP BY GROUPING SETS (
        (month_start),
        (month_start, persona),
        (month_start, initial_subscription_group),
        (month_start, persona, initial_subscription_group)
    )
)
SELECT
    *,
    ROUND(
        100.0 * churned_during_month / NULLIF(active_at_start, 0),
        2
    ) AS monthly_logo_churn_rate_pct
FROM aggregated
ORDER BY month_start, segment_level, persona, initial_subscription_group;

-- ============================================================
-- 4. REVENUE TRENDS BY SEGMENT AND REVENUE TYPE
-- ============================================================

CREATE OR REPLACE TABLE eda_revenue_trends_by_segment_type AS
WITH base AS (
    SELECT
        r.revenue_month,
        c.persona,
        c.initial_subscription_group,
        COUNT(DISTINCT r.company_profile_id) AS revenue_companies,
        SUM(r.subscription_revenue) AS subscription,
        SUM(r.interchange_revenue) AS interchange,
        SUM(r.banking_fees) AS banking_fees,
        SUM(r.deposit_interest_revenue) AS deposit_interest,
        SUM(r.total_revenue) AS total_revenue
    FROM revenue_with_total r
    JOIN companies c USING (company_profile_id)
    WHERE r.revenue_month
          <= (SELECT confirmed_end_month FROM analysis_parameters)
    GROUP BY r.revenue_month, c.persona, c.initial_subscription_group
),
long_form AS (
    SELECT revenue_month, persona, initial_subscription_group,
           revenue_companies, 'Subscription' AS revenue_type,
           subscription AS revenue
    FROM base
    UNION ALL
    SELECT revenue_month, persona, initial_subscription_group,
           revenue_companies, 'Interchange', interchange
    FROM base
    UNION ALL
    SELECT revenue_month, persona, initial_subscription_group,
           revenue_companies, 'Banking fees', banking_fees
    FROM base
    UNION ALL
    SELECT revenue_month, persona, initial_subscription_group,
           revenue_companies, 'Deposit interest', deposit_interest
    FROM base
    UNION ALL
    SELECT revenue_month, persona, initial_subscription_group,
           revenue_companies, 'Total revenue', total_revenue
    FROM base
)
SELECT
    revenue_month,
    persona,
    initial_subscription_group,
    revenue_type,
    revenue_companies,
    revenue,
    revenue / NULLIF(revenue_companies, 0)
        AS revenue_per_revenue_company
FROM long_form
ORDER BY
    revenue_month,
    persona,
    initial_subscription_group,
    revenue_type;

-- ============================================================
-- 5. OBSERVED LTV PROXY BY COHORT AGE, SEGMENT, AND REVENUE TYPE
-- ============================================================
-- This is not forecast LTV. It is cumulative observed revenue divided by the
-- original activated cohort size. A complete company-month spine treats absent
-- revenue rows as zero for this explicit sensitivity definition.

CREATE OR REPLACE TABLE eda_ltv_proxy_by_cohort_age_segment_type AS
WITH eligible_companies AS (
    SELECT
        c.company_profile_id,
        c.persona,
        c.initial_subscription_group,
        DATE_TRUNC('month', c.activation_date)::DATE AS activation_month
    FROM companies c
    WHERE c.activation_date IS NOT NULL
      AND DATE_TRUNC('month', c.activation_date)::DATE
          <= (SELECT confirmed_end_month FROM analysis_parameters)
),
company_spine AS (
    SELECT
        c.company_profile_id,
        c.persona,
        c.initial_subscription_group,
        c.activation_month,
        gs.revenue_month::DATE AS revenue_month,
        DATE_DIFF('month', c.activation_month, gs.revenue_month::DATE)
            AS months_since_activation
    FROM eligible_companies c,
    LATERAL GENERATE_SERIES(
        c.activation_month,
        (SELECT confirmed_end_month FROM analysis_parameters),
        INTERVAL '1 month'
    ) AS gs(revenue_month)
),
company_month AS (
    SELECT
        s.*,
        COALESCE(r.subscription_revenue, 0) AS subscription,
        COALESCE(r.interchange_revenue, 0) AS interchange,
        COALESCE(r.banking_fees, 0) AS banking_fees,
        COALESCE(r.deposit_interest_revenue, 0) AS deposit_interest,
        COALESCE(r.total_revenue, 0) AS total_revenue
    FROM company_spine s
    LEFT JOIN revenue_with_total r
        ON s.company_profile_id = r.company_profile_id
       AND s.revenue_month = r.revenue_month
),
aggregated AS (
    SELECT
        activation_month,
        months_since_activation,
        CASE WHEN GROUPING(persona) = 1 THEN 'ALL' ELSE persona END AS persona,
        CASE
            WHEN GROUPING(initial_subscription_group) = 1 THEN 'ALL'
            ELSE initial_subscription_group
        END AS initial_subscription_group,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1 THEN 'overall'
            WHEN GROUPING(persona) = 0
             AND GROUPING(initial_subscription_group) = 1 THEN 'persona'
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 0 THEN 'initial_plan'
            ELSE 'persona_x_initial_plan'
        END AS segment_level,
        COUNT(DISTINCT company_profile_id) AS activated_cohort_size,
        SUM(subscription) AS subscription,
        SUM(interchange) AS interchange,
        SUM(banking_fees) AS banking_fees,
        SUM(deposit_interest) AS deposit_interest,
        SUM(total_revenue) AS total_revenue
    FROM company_month
    GROUP BY GROUPING SETS (
        (activation_month, months_since_activation),
        (activation_month, months_since_activation, persona),
        (
            activation_month,
            months_since_activation,
            initial_subscription_group
        ),
        (
            activation_month,
            months_since_activation,
            persona,
            initial_subscription_group
        )
    )
),
long_form AS (
    SELECT *, 'Subscription' AS revenue_type, subscription AS monthly_revenue
    FROM aggregated
    UNION ALL
    SELECT *, 'Interchange', interchange FROM aggregated
    UNION ALL
    SELECT *, 'Banking fees', banking_fees FROM aggregated
    UNION ALL
    SELECT *, 'Deposit interest', deposit_interest FROM aggregated
    UNION ALL
    SELECT *, 'Total revenue', total_revenue FROM aggregated
),
with_cumulative AS (
    SELECT
        activation_month,
        months_since_activation,
        persona,
        initial_subscription_group,
        segment_level,
        revenue_type,
        activated_cohort_size,
        monthly_revenue,
        SUM(monthly_revenue) OVER (
            PARTITION BY
                activation_month,
                persona,
                initial_subscription_group,
                segment_level,
                revenue_type
            ORDER BY months_since_activation
        ) AS cumulative_revenue
    FROM long_form
)
SELECT
    activation_month,
    months_since_activation,
    persona,
    initial_subscription_group,
    segment_level,
    revenue_type,
    activated_cohort_size,
    monthly_revenue,
    cumulative_revenue,
    cumulative_revenue / NULLIF(activated_cohort_size, 0)
        AS observed_ltv_per_activated_company
FROM with_cumulative
ORDER BY
    activation_month,
    months_since_activation,
    segment_level,
    persona,
    initial_subscription_group,
    revenue_type;

-- ============================================================
-- 6. COMPACT SEGMENT SCORECARD
-- ============================================================
-- This is the easiest output to scan when choosing a persona or initial-plan
-- story. Funnel rates pool counts before calculating percentages.

CREATE OR REPLACE TABLE eda_segment_scorecard AS
WITH funnel AS (
    SELECT
        segment_level,
        persona,
        initial_subscription_group,
        SUM(eligible_signups) AS eligible_signups_30d,
        ROUND(
            100.0 * (SUM(eligible_signups) - SUM(activated_within_30d))
            / NULLIF(SUM(eligible_signups), 0),
            1
        ) AS total_funnel_dropout_30d_pct,
        ROUND(
            100.0 * SUM(pre_activation_closed_within_30d)
            / NULLIF(SUM(eligible_signups), 0),
            1
        ) AS pre_activation_closure_30d_pct
    FROM eda_funnel_30d_by_signup_month_segment
    WHERE segment_level IN ('persona', 'initial_plan')
    GROUP BY segment_level, persona, initial_subscription_group
),
new_companies AS (
    SELECT
        segment_level,
        persona,
        initial_subscription_group,
        new_companies AS april_new_companies
    FROM eda_new_companies_by_month_segment
    WHERE segment_level IN ('persona', 'initial_plan')
      AND signup_month = (SELECT confirmed_end_month FROM analysis_parameters)
),
churn AS (
    SELECT
        segment_level,
        persona,
        initial_subscription_group,
        active_at_start AS april_active_at_start,
        churned_during_month AS april_churned,
        monthly_logo_churn_rate_pct AS april_logo_churn_rate_pct
    FROM eda_churn_monthly_by_segment
    WHERE segment_level IN ('persona', 'initial_plan')
      AND month_start = (SELECT confirmed_end_month FROM analysis_parameters)
),
april_revenue AS (
    SELECT
        'persona' AS segment_level,
        persona,
        'ALL' AS initial_subscription_group,
        revenue_companies AS april_revenue_companies,
        total_revenue AS april_total_revenue,
        average_revenue_per_company AS april_revenue_per_company
    FROM eda_april_revenue_by_persona
    UNION ALL
    SELECT
        'initial_plan',
        'ALL',
        initial_subscription_group,
        revenue_companies,
        total_revenue,
        average_revenue_per_company
    FROM eda_april_revenue_by_initial_plan
),
ltv AS (
    SELECT
        segment_level,
        persona,
        initial_subscription_group,
        SUM(activated_cohort_size) AS age_3_companies,
        ROUND(
            SUM(cumulative_revenue) / NULLIF(SUM(activated_cohort_size), 0),
            2
        ) AS observed_ltv_proxy_at_age_3
    FROM eda_ltv_proxy_by_cohort_age_segment_type
    WHERE segment_level IN ('persona', 'initial_plan')
      AND revenue_type = 'Total revenue'
      AND months_since_activation = 3
    GROUP BY segment_level, persona, initial_subscription_group
)
SELECT
    f.segment_level,
    f.persona,
    f.initial_subscription_group,
    f.eligible_signups_30d,
    f.total_funnel_dropout_30d_pct,
    f.pre_activation_closure_30d_pct,
    n.april_new_companies,
    c.april_active_at_start,
    c.april_churned,
    c.april_logo_churn_rate_pct,
    r.april_revenue_companies,
    r.april_total_revenue,
    r.april_revenue_per_company,
    l.age_3_companies,
    l.observed_ltv_proxy_at_age_3
FROM funnel f
LEFT JOIN new_companies n USING (
    segment_level,
    persona,
    initial_subscription_group
)
LEFT JOIN churn c USING (
    segment_level,
    persona,
    initial_subscription_group
)
LEFT JOIN april_revenue r USING (
    segment_level,
    persona,
    initial_subscription_group
)
LEFT JOIN ltv l USING (
    segment_level,
    persona,
    initial_subscription_group
)
ORDER BY segment_level, april_total_revenue DESC;
