-- Full-period revenue-health classification using only the two case tables:
--   1. companies
--   2. revenue_with_total
--
-- The confirmed cutoff is April 2026. May is deliberately excluded.
-- A company becomes comparable only after three complete post-activation
-- months are available before the observation month. Because the extract
-- begins in October 2025, February-April are the reliable trend months.
--
-- This is a revenue-health proxy, not contractual customer health or confirmed
-- churn. A missing revenue row is treated as no observed revenue for the month.

WITH parameters AS (
    SELECT
        DATE '2025-10-01' AS extract_start_month,
        DATE '2026-04-01' AS confirmed_end_month,
        3::INTEGER AS trailing_baseline_months,
        3::INTEGER AS churned_after_inactive_months,
        0.30::DECIMAL(5, 4) AS relative_decline_threshold,
        10.00::DECIMAL(38, 20) AS minimum_eur_decline
),
eligible_companies AS (
    SELECT
        company_profile_id,
        persona,
        initial_subscription_group,
        DATE_TRUNC('month', activation_date)::DATE AS activation_month
    FROM companies
    WHERE activation_date IS NOT NULL
      AND DATE_TRUNC('month', activation_date)::DATE
          <= (SELECT confirmed_end_month FROM parameters)
),
company_month_spine AS (
    SELECT
        c.company_profile_id,
        c.persona,
        c.initial_subscription_group,
        c.activation_month,
        month_series.observation_month::DATE AS observation_month
    FROM eligible_companies c,
    LATERAL GENERATE_SERIES(
        GREATEST(
            c.activation_month,
            (SELECT extract_start_month FROM parameters)
        ),
        (SELECT confirmed_end_month FROM parameters),
        INTERVAL '1 month'
    ) AS month_series(observation_month)
),
monthly_revenue AS (
    SELECT
        company_profile_id,
        revenue_month,
        SUM(total_revenue) AS total_revenue
    FROM revenue_with_total
    WHERE revenue_month <= (SELECT confirmed_end_month FROM parameters)
    GROUP BY company_profile_id, revenue_month
),
company_month AS (
    SELECT
        s.*,
        r.company_profile_id IS NOT NULL AS has_revenue_this_month,
        COALESCE(r.total_revenue, 0) AS total_revenue
    FROM company_month_spine s
    LEFT JOIN monthly_revenue r
        ON s.company_profile_id = r.company_profile_id
       AND s.observation_month = r.revenue_month
),
history_metrics AS (
    SELECT
        *,
        COUNT(*) OVER (
            PARTITION BY company_profile_id
            ORDER BY observation_month
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS baseline_months,
        MEDIAN(total_revenue) OVER (
            PARTITION BY company_profile_id
            ORDER BY observation_month
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS trailing_3m_median_revenue,
        MAX(
            CASE WHEN has_revenue_this_month THEN observation_month END
        ) OVER (
            PARTITION BY company_profile_id
            ORDER BY observation_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS last_revenue_month_to_date,
        SUM(
            CASE
                WHEN NOT has_revenue_this_month THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY company_profile_id
            ORDER BY observation_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prior_missing_observed_months
    FROM company_month
),
comparable_snapshots AS (
    SELECT *
    FROM history_metrics
    WHERE DATE_DIFF('month', activation_month, observation_month)
          >= 1 + (SELECT trailing_baseline_months FROM parameters)
),
classified AS (
    SELECT
        *,
        CASE
            WHEN last_revenue_month_to_date IS NULL
                THEN 'Never monetized'
            WHEN has_revenue_this_month
             AND prior_missing_observed_months > 0
                THEN 'Recovered / monitor'
            WHEN has_revenue_this_month
             AND baseline_months = (
                    SELECT trailing_baseline_months FROM parameters
                 )
             AND trailing_3m_median_revenue > 0
             AND total_revenue <= trailing_3m_median_revenue * (
                    1 - (SELECT relative_decline_threshold FROM parameters)
                 )
             AND trailing_3m_median_revenue - total_revenue >= (
                    SELECT minimum_eur_decline FROM parameters
                 )
                THEN 'Watch - revenue declining'
            WHEN has_revenue_this_month
                THEN 'Healthy revenue account'
            WHEN DATE_DIFF(
                    'month',
                    last_revenue_month_to_date,
                    observation_month
                 ) < (
                    SELECT churned_after_inactive_months FROM parameters
                 )
                THEN 'At-risk'
            ELSE 'Churned proxy'
        END AS account_health_state
    FROM comparable_snapshots
),
snapshot_aggregated AS (
    SELECT
        observation_month,
        account_health_state,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1
                THEN 'overall'
            WHEN GROUPING(persona) = 0 THEN 'persona'
            ELSE 'initial_plan'
        END AS segment_level,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1
                THEN 'ALL'
            WHEN GROUPING(persona) = 0 THEN persona
            ELSE initial_subscription_group
        END AS segment,
        COUNT(*) AS companies
    FROM classified
    GROUP BY GROUPING SETS (
        (observation_month, account_health_state),
        (observation_month, account_health_state, persona),
        (
            observation_month,
            account_health_state,
            initial_subscription_group
        )
    )
),
fixed_cohort_trend AS (
    SELECT
        observation_month,
        account_health_state,
        'fixed_cohort_trend' AS segment_level,
        'October activation cohort' AS segment,
        COUNT(*) AS companies
    FROM classified
    WHERE activation_month
          = (SELECT extract_start_month FROM parameters)
    GROUP BY observation_month, account_health_state
),
aggregated AS (
    SELECT * FROM snapshot_aggregated
    UNION ALL
    SELECT * FROM fixed_cohort_trend
)
SELECT
    *,
    ROUND(
        100.0 * companies
        / SUM(companies) OVER (
            PARTITION BY observation_month, segment_level, segment
        ),
        2
    ) AS company_share_pct
FROM aggregated
ORDER BY
    observation_month,
    segment_level,
    segment,
    CASE account_health_state
        WHEN 'Healthy revenue account' THEN 1
        WHEN 'Watch - revenue declining' THEN 2
        WHEN 'Recovered / monitor' THEN 3
        WHEN 'At-risk' THEN 4
        WHEN 'Churned proxy' THEN 5
        ELSE 6
    END;
