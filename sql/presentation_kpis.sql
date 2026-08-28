-- Presentation KPI layer
-- Runs after cohort, streak, and revenue-concentration analyses.

-- A single company-level source of truth for the lifecycle language used in the
-- presentation. "Healthy" is a revenue-health proxy, not a bank-account,
-- satisfaction, profitability, or contractual-status assessment.
CREATE OR REPLACE TABLE eda_company_account_health_at_cutoff AS
SELECT
    s.company_profile_id,
    s.persona,
    s.initial_subscription_group,
    s.activation_month,
    s.months_since_activation,
    s.has_revenue_this_month,
    s.current_active_streak_months,
    s.maximum_active_streak_to_date,
    s.continuously_active_since_activation,
    s.reactivated_active,
    s.revenue_lifecycle_state,
    CASE
        WHEN s.revenue_lifecycle_state = 'Never monetized'
            THEN 'Never monetized'
        WHEN s.has_revenue_this_month
         AND s.continuously_active_since_activation
            THEN 'Healthy revenue account'
        WHEN s.has_revenue_this_month
            THEN 'Recovered / monitor'
        WHEN s.revenue_lifecycle_state = 'At-risk'
            THEN 'At-risk'
        ELSE 'Churned proxy'
    END AS account_health_state,
    s.total_revenue AS cutoff_month_revenue,
    l.first_revenue_month,
    l.last_revenue_month,
    l.inactive_months_at_cutoff,
    l.last_total_revenue AS last_observed_month_revenue,
    r.cumulative_total_revenue,
    COALESCE(r.is_top_10pct, FALSE) AS is_top_10pct,
    COALESCE(r.is_top_20pct, FALSE) AS is_top_20pct
FROM eda_company_revenue_streaks s
LEFT JOIN eda_company_revenue_lifecycle_state l
    USING (company_profile_id)
LEFT JOIN eda_company_cumulative_revenue_rank r
    USING (company_profile_id)
WHERE s.observation_month
      = (SELECT confirmed_end_month FROM analysis_parameters)
ORDER BY s.company_profile_id;

CREATE OR REPLACE TABLE eda_account_health_by_segment AS
WITH aggregated AS (
    SELECT
        account_health_state,
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
        SUM(cutoff_month_revenue) AS cutoff_month_revenue,
        SUM(cumulative_total_revenue) AS cumulative_revenue,
        SUM(last_observed_month_revenue) AS last_observed_month_revenue
    FROM eda_company_account_health_at_cutoff
    GROUP BY GROUPING SETS (
        (account_health_state),
        (account_health_state, persona),
        (account_health_state, initial_subscription_group),
        (account_health_state, persona, initial_subscription_group)
    )
)
SELECT
    *,
    ROUND(
        100.0 * companies / SUM(companies) OVER (
            PARTITION BY
                segment_level,
                persona,
                initial_subscription_group
        ),
        2
    ) AS segment_company_share_pct
FROM aggregated
ORDER BY
    segment_level,
    persona,
    initial_subscription_group,
    CASE account_health_state
        WHEN 'Healthy revenue account' THEN 1
        WHEN 'Recovered / monitor' THEN 2
        WHEN 'At-risk' THEN 3
        WHEN 'Churned proxy' THEN 4
        ELSE 5
    END;

-- Immediate health of the cumulative top-20 revenue population. Historical
-- cumulative revenue describes value concentration; last-observed-month revenue
-- is only an exposure proxy for inactive companies, not forecast lost revenue.
CREATE OR REPLACE TABLE eda_top20_account_health_summary AS
WITH aggregated AS (
    SELECT
        account_health_state,
        COUNT(*) AS companies,
        SUM(cumulative_total_revenue) AS cumulative_revenue,
        SUM(cutoff_month_revenue) AS cutoff_month_revenue,
        SUM(last_observed_month_revenue) AS last_observed_month_revenue
    FROM eda_company_account_health_at_cutoff
    WHERE is_top_20pct
    GROUP BY account_health_state
)
SELECT
    *,
    ROUND(100.0 * companies / SUM(companies) OVER (), 2)
        AS top_20pct_company_share_pct,
    ROUND(
        100.0 * cumulative_revenue / SUM(cumulative_revenue) OVER (),
        2
    ) AS top_20pct_historical_revenue_share_pct
FROM aggregated
ORDER BY CASE account_health_state
    WHEN 'Healthy revenue account' THEN 1
    WHEN 'Recovered / monitor' THEN 2
    WHEN 'At-risk' THEN 3
    WHEN 'Churned proxy' THEN 4
    ELSE 5
END;
