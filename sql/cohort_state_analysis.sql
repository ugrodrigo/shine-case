-- Shine case: cohort analysis using revenue lifecycle states
-- Runs after shine_eda.sql and kpi_deep_dive.sql.
-- Cohorts are based on activation month because the states describe post-
-- activation revenue behavior. Core analysis ends in April 2026.

-- ============================================================
-- 1. COMPANY x COHORT-AGE MONTHLY STATE
-- ============================================================
-- States:
--   Never monetized: activated but no revenue observed yet
--   Active: revenue in the observation month
--   At-risk: last revenue was 1-2 months earlier
--   Churned proxy: last revenue was 3+ months earlier

CREATE OR REPLACE TABLE eda_company_cohort_month_state AS
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
spine AS (
    SELECT
        c.company_profile_id,
        c.persona,
        c.initial_subscription_group,
        c.activation_month,
        gs.observation_month::DATE AS observation_month,
        DATE_DIFF(
            'month',
            c.activation_month,
            gs.observation_month::DATE
        ) AS months_since_activation
    FROM eligible_companies c,
    LATERAL GENERATE_SERIES(
        c.activation_month,
        (SELECT confirmed_end_month FROM analysis_parameters),
        INTERVAL '1 month'
    ) AS gs(observation_month)
),
with_revenue AS (
    SELECT
        s.*,
        r.company_profile_id IS NOT NULL AS has_revenue_this_month,
        r.revenue_month,
        COALESCE(r.subscription_revenue, 0) AS subscription_revenue,
        COALESCE(r.interchange_revenue, 0) AS interchange_revenue,
        COALESCE(r.banking_fees, 0) AS banking_fees,
        COALESCE(r.deposit_interest_revenue, 0) AS deposit_interest_revenue,
        COALESCE(r.total_revenue, 0) AS total_revenue
    FROM spine s
    LEFT JOIN revenue_with_total r
        ON s.company_profile_id = r.company_profile_id
       AND s.observation_month = r.revenue_month
),
with_last_revenue AS (
    SELECT
        *,
        MAX(revenue_month) OVER (
            PARTITION BY company_profile_id
            ORDER BY observation_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS last_revenue_month_to_date
    FROM with_revenue
)
SELECT
    *,
    CASE
        WHEN has_revenue_this_month THEN 'Active'
        WHEN last_revenue_month_to_date IS NULL THEN 'Never monetized'
        WHEN DATE_DIFF(
            'month',
            last_revenue_month_to_date,
            observation_month
        ) < (SELECT churned_after_inactive_months FROM revenue_state_parameters)
            THEN 'At-risk'
        ELSE 'Churned proxy'
    END AS revenue_lifecycle_state
FROM with_last_revenue
ORDER BY company_profile_id, observation_month;

-- ============================================================
-- 2. STATE DISTRIBUTION BY COHORT, AGE, AND SEGMENT
-- ============================================================

CREATE OR REPLACE TABLE eda_cohort_state_distribution_by_segment AS
WITH aggregated AS (
    SELECT
        activation_month,
        observation_month,
        months_since_activation,
        revenue_lifecycle_state,
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
        COUNT(*) AS companies,
        SUM(subscription_revenue) AS subscription_revenue,
        SUM(interchange_revenue) AS interchange_revenue,
        SUM(banking_fees) AS banking_fees,
        SUM(deposit_interest_revenue) AS deposit_interest_revenue,
        SUM(total_revenue) AS total_revenue
    FROM eda_company_cohort_month_state
    GROUP BY GROUPING SETS (
        (
            activation_month,
            observation_month,
            months_since_activation,
            revenue_lifecycle_state
        ),
        (
            activation_month,
            observation_month,
            months_since_activation,
            revenue_lifecycle_state,
            persona
        ),
        (
            activation_month,
            observation_month,
            months_since_activation,
            revenue_lifecycle_state,
            initial_subscription_group
        ),
        (
            activation_month,
            observation_month,
            months_since_activation,
            revenue_lifecycle_state,
            persona,
            initial_subscription_group
        )
    )
)
SELECT
    *,
    SUM(companies) OVER (
        PARTITION BY
            activation_month,
            observation_month,
            months_since_activation,
            segment_level,
            persona,
            initial_subscription_group
    ) AS activated_cohort_size,
    ROUND(
        100.0 * companies
        / SUM(companies) OVER (
            PARTITION BY
                activation_month,
                observation_month,
                months_since_activation,
                segment_level,
                persona,
                initial_subscription_group
        ),
        2
    ) AS cohort_state_share_pct
FROM aggregated
ORDER BY
    activation_month,
    months_since_activation,
    segment_level,
    persona,
    initial_subscription_group,
    revenue_lifecycle_state;

-- Presentation-friendly wide state matrix. Revenue is divided by the full
-- original activated cohort, not just companies with a revenue row.
CREATE OR REPLACE TABLE eda_cohort_state_matrix_by_segment AS
SELECT
    activation_month,
    observation_month,
    months_since_activation,
    segment_level,
    persona,
    initial_subscription_group,
    MAX(activated_cohort_size) AS activated_cohort_size,
    COALESCE(
        SUM(companies) FILTER (WHERE revenue_lifecycle_state = 'Active'),
        0
    ) AS active_companies,
    COALESCE(
        SUM(companies) FILTER (WHERE revenue_lifecycle_state = 'At-risk'),
        0
    ) AS at_risk_companies,
    COALESCE(
        SUM(companies) FILTER (WHERE revenue_lifecycle_state = 'Churned proxy'),
        0
    ) AS churned_proxy_companies,
    COALESCE(
        SUM(companies) FILTER (WHERE revenue_lifecycle_state = 'Never monetized'),
        0
    ) AS never_monetized_companies,
    COALESCE(
        MAX(cohort_state_share_pct) FILTER (
            WHERE revenue_lifecycle_state = 'Active'
        ),
        0
    ) AS active_share_pct,
    COALESCE(
        MAX(cohort_state_share_pct) FILTER (
            WHERE revenue_lifecycle_state = 'At-risk'
        ),
        0
    ) AS at_risk_share_pct,
    COALESCE(
        MAX(cohort_state_share_pct) FILTER (
            WHERE revenue_lifecycle_state = 'Churned proxy'
        ),
        0
    ) AS churned_proxy_share_pct,
    COALESCE(
        MAX(cohort_state_share_pct) FILTER (
            WHERE revenue_lifecycle_state = 'Never monetized'
        ),
        0
    ) AS never_monetized_share_pct,
    SUM(subscription_revenue) AS subscription_revenue,
    SUM(interchange_revenue) AS interchange_revenue,
    SUM(banking_fees) AS banking_fees,
    SUM(deposit_interest_revenue) AS deposit_interest_revenue,
    SUM(total_revenue) AS total_revenue,
    SUM(total_revenue) / NULLIF(MAX(activated_cohort_size), 0)
        AS revenue_per_original_activated_company
FROM eda_cohort_state_distribution_by_segment
GROUP BY
    activation_month,
    observation_month,
    months_since_activation,
    segment_level,
    persona,
    initial_subscription_group
ORDER BY
    activation_month,
    months_since_activation,
    segment_level,
    persona,
    initial_subscription_group;

-- ============================================================
-- 3. STATE TRANSITIONS BY COHORT AGE
-- ============================================================
-- Includes recoveries such as At-risk -> Active and Churned proxy -> Active.

CREATE OR REPLACE TABLE eda_cohort_state_transitions_by_segment AS
WITH history AS (
    SELECT
        *,
        LAG(revenue_lifecycle_state) OVER (
            PARTITION BY company_profile_id
            ORDER BY observation_month
        ) AS prior_revenue_lifecycle_state
    FROM eda_company_cohort_month_state
),
aggregated AS (
    SELECT
        activation_month,
        observation_month,
        months_since_activation,
        prior_revenue_lifecycle_state,
        revenue_lifecycle_state,
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
        COUNT(*) AS companies
    FROM history
    WHERE prior_revenue_lifecycle_state IS NOT NULL
    GROUP BY GROUPING SETS (
        (
            activation_month,
            observation_month,
            months_since_activation,
            prior_revenue_lifecycle_state,
            revenue_lifecycle_state
        ),
        (
            activation_month,
            observation_month,
            months_since_activation,
            prior_revenue_lifecycle_state,
            revenue_lifecycle_state,
            persona
        ),
        (
            activation_month,
            observation_month,
            months_since_activation,
            prior_revenue_lifecycle_state,
            revenue_lifecycle_state,
            initial_subscription_group
        ),
        (
            activation_month,
            observation_month,
            months_since_activation,
            prior_revenue_lifecycle_state,
            revenue_lifecycle_state,
            persona,
            initial_subscription_group
        )
    )
)
SELECT
    *,
    ROUND(
        100.0 * companies
        / SUM(companies) OVER (
            PARTITION BY
                activation_month,
                observation_month,
                months_since_activation,
                prior_revenue_lifecycle_state,
                segment_level,
                persona,
                initial_subscription_group
        ),
        2
    ) AS transition_rate_from_prior_state_pct
FROM aggregated
ORDER BY
    activation_month,
    months_since_activation,
    segment_level,
    persona,
    initial_subscription_group,
    prior_revenue_lifecycle_state,
    revenue_lifecycle_state;
