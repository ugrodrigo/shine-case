-- Shine case: consecutive revenue-activity streak analysis
-- Runs after sql/cohort_state_analysis.sql and uses the same April cutoff.
--
-- A revenue-active month is a month with a revenue row. There are no rows with
-- exactly zero total revenue through April, so this is also a non-zero revenue
-- month in the current extract.

-- ============================================================
-- 1. COMPANY x MONTH STREAKS
-- ============================================================

CREATE OR REPLACE TABLE eda_company_revenue_streaks AS
WITH grouped AS (
    SELECT
        *,
        SUM(CASE WHEN has_revenue_this_month THEN 0 ELSE 1 END) OVER (
            PARTITION BY company_profile_id
            ORDER BY observation_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS active_sequence_group,
        SUM(CASE WHEN has_revenue_this_month THEN 0 ELSE 1 END) OVER (
            PARTITION BY company_profile_id
            ORDER BY observation_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) = 0 AS continuously_active_since_activation
    FROM eda_company_cohort_month_state
),
with_current_streak AS (
    SELECT
        *,
        CASE
            WHEN has_revenue_this_month THEN COUNT(*) FILTER (
                WHERE has_revenue_this_month
            ) OVER (
                PARTITION BY company_profile_id, active_sequence_group
                ORDER BY observation_month
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            )
            ELSE 0
        END AS current_active_streak_months
    FROM grouped
)
SELECT
    *,
    MAX(current_active_streak_months) OVER (
        PARTITION BY company_profile_id
        ORDER BY observation_month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS maximum_active_streak_to_date,
    has_revenue_this_month
        AND NOT continuously_active_since_activation AS reactivated_active,
    LEAD(has_revenue_this_month) OVER (
        PARTITION BY company_profile_id
        ORDER BY observation_month
    ) AS active_next_month
FROM with_current_streak
ORDER BY company_profile_id, observation_month;

-- ============================================================
-- 2. COHORT LOYALTY CURVE
-- ============================================================
-- One row per activation cohort, customer age, and segment. Continuous-active
-- share is the strict loyalty measure: revenue in every observed month since
-- activation, divided by the entire original activated cohort.

CREATE OR REPLACE TABLE eda_cohort_streaks_by_segment AS
SELECT
    activation_month,
    observation_month,
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
    COUNT(*) AS activated_cohort_size,
    COUNT(*) FILTER (WHERE has_revenue_this_month) AS active_companies,
    COUNT(*) FILTER (WHERE continuously_active_since_activation)
        AS continuously_active_companies,
    COUNT(*) FILTER (WHERE reactivated_active) AS reactivated_active_companies,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE has_revenue_this_month) / COUNT(*),
        2
    ) AS active_share_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE continuously_active_since_activation)
        / COUNT(*),
        2
    ) AS continuously_active_share_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE reactivated_active) / COUNT(*),
        2
    ) AS reactivated_active_share_pct,
    ROUND(
        AVG(current_active_streak_months) FILTER (
            WHERE has_revenue_this_month
        ),
        2
    ) AS average_current_streak_among_active,
    SUM(total_revenue) AS total_revenue,
    SUM(total_revenue) / NULLIF(COUNT(*), 0)
        AS monthly_revenue_per_original_activated_company
FROM eda_company_revenue_streaks
GROUP BY GROUPING SETS (
    (activation_month, observation_month, months_since_activation),
    (activation_month, observation_month, months_since_activation, persona),
    (
        activation_month,
        observation_month,
        months_since_activation,
        initial_subscription_group
    ),
    (
        activation_month,
        observation_month,
        months_since_activation,
        persona,
        initial_subscription_group
    )
)
ORDER BY
    activation_month,
    months_since_activation,
    segment_level,
    persona,
    initial_subscription_group;

-- ============================================================
-- 3. DOES A LONGER STREAK PREDICT NEXT-MONTH ACTIVITY?
-- ============================================================
-- Only active company-months with an observable next month are eligible.
-- Customer age is retained so comparisons can control for tenure.

CREATE OR REPLACE TABLE eda_streak_next_month_persistence_by_segment AS
SELECT
    months_since_activation,
    current_active_streak_months,
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
    COUNT(*) AS eligible_active_company_months,
    COUNT(*) FILTER (WHERE active_next_month) AS active_next_months,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE active_next_month) / COUNT(*),
        2
    ) AS next_month_active_rate_pct
FROM eda_company_revenue_streaks
WHERE has_revenue_this_month
  AND active_next_month IS NOT NULL
GROUP BY GROUPING SETS (
    (months_since_activation, current_active_streak_months),
    (months_since_activation, current_active_streak_months, persona),
    (
        months_since_activation,
        current_active_streak_months,
        initial_subscription_group
    ),
    (
        months_since_activation,
        current_active_streak_months,
        persona,
        initial_subscription_group
    )
)
ORDER BY
    months_since_activation,
    current_active_streak_months,
    segment_level,
    persona,
    initial_subscription_group;

-- ============================================================
-- 4. AGE-THREE LOYALTY SCORECARD
-- ============================================================
-- Age three is shared by four cohorts (October-January), providing a useful
-- balance between maturation and sample size.

CREATE OR REPLACE TABLE eda_age3_streak_scorecard AS
SELECT
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
    COUNT(*) FILTER (WHERE has_revenue_this_month) AS active_companies,
    COUNT(*) FILTER (WHERE continuously_active_since_activation)
        AS continuously_active_companies,
    COUNT(*) FILTER (WHERE reactivated_active) AS reactivated_active_companies,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE has_revenue_this_month) / COUNT(*),
        2
    ) AS active_share_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE continuously_active_since_activation)
        / COUNT(*),
        2
    ) AS continuously_active_share_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE reactivated_active) / COUNT(*),
        2
    ) AS reactivated_active_share_pct,
    ROUND(
        AVG(current_active_streak_months) FILTER (
            WHERE has_revenue_this_month
        ),
        2
    ) AS average_current_streak_among_active,
    SUM(total_revenue) AS total_revenue,
    SUM(total_revenue) / NULLIF(COUNT(*), 0)
        AS monthly_revenue_per_original_activated_company
FROM eda_company_revenue_streaks
WHERE months_since_activation = 3
GROUP BY GROUPING SETS (
    (),
    (persona),
    (initial_subscription_group),
    (persona, initial_subscription_group)
)
ORDER BY segment_level, persona, initial_subscription_group;
