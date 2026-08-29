-- Presentation KPI layer
-- Runs after cohort, streak, and revenue-concentration analyses.

-- Revenue momentum is an overlay, not a churn definition. It compares April
-- revenue with the median of the three prior complete calendar months. The
-- activation month is excluded because monthly revenue cannot be split at the
-- exact activation date. The €10 floor prevents immaterial percentage changes
-- on very small values from creating a warning.
CREATE OR REPLACE TABLE account_health_parameters AS
SELECT
    3::INTEGER AS trailing_complete_months,
    0.30::DECIMAL(5, 4) AS relative_decline_threshold,
    10.00::DECIMAL(38, 20) AS minimum_eur_decline;

CREATE OR REPLACE TABLE eda_company_revenue_momentum_at_cutoff AS
WITH prior_complete_months AS (
    SELECT
        s.company_profile_id,
        s.observation_month,
        s.total_revenue,
        ROW_NUMBER() OVER (
            PARTITION BY s.company_profile_id
            ORDER BY s.observation_month DESC
        ) AS recency_rank
    FROM eda_company_revenue_streaks s
    WHERE s.observation_month
              < (SELECT confirmed_end_month FROM analysis_parameters)
      AND s.observation_month > s.activation_month
),
baseline AS (
    SELECT
        company_profile_id,
        COUNT(*) FILTER (
            WHERE recency_rank <= (
                SELECT trailing_complete_months FROM account_health_parameters
            )
        ) AS baseline_months,
        MEDIAN(total_revenue) FILTER (
            WHERE recency_rank <= (
                SELECT trailing_complete_months FROM account_health_parameters
            )
        ) AS trailing_3m_median_revenue,
        AVG(total_revenue) FILTER (
            WHERE recency_rank <= (
                SELECT trailing_complete_months FROM account_health_parameters
            )
        ) AS trailing_3m_average_revenue
    FROM prior_complete_months
    GROUP BY company_profile_id
)
SELECT
    s.company_profile_id,
    s.persona,
    s.initial_subscription_group,
    s.activation_month,
    s.has_revenue_this_month,
    s.continuously_active_since_activation,
    s.reactivated_active,
    s.total_revenue AS cutoff_month_revenue,
    COALESCE(b.baseline_months, 0) AS baseline_months,
    b.trailing_3m_median_revenue,
    b.trailing_3m_average_revenue,
    s.total_revenue - b.trailing_3m_median_revenue
        AS revenue_change_vs_trailing_median,
    ROUND(
        100.0 * (
            s.total_revenue / NULLIF(b.trailing_3m_median_revenue, 0) - 1
        ),
        2
    ) AS revenue_change_vs_trailing_median_pct,
    CASE
        WHEN NOT s.has_revenue_this_month THEN 'Not currently active'
        WHEN COALESCE(b.baseline_months, 0) < (
            SELECT trailing_complete_months FROM account_health_parameters
        ) THEN 'Insufficient history'
        WHEN b.trailing_3m_median_revenue <= 0 THEN 'Insufficient baseline'
        WHEN s.total_revenue <= b.trailing_3m_median_revenue * (
                1 - (
                    SELECT relative_decline_threshold
                    FROM account_health_parameters
                )
             )
         AND b.trailing_3m_median_revenue - s.total_revenue >= (
                SELECT minimum_eur_decline FROM account_health_parameters
             ) THEN 'Declining'
        WHEN s.total_revenue >= b.trailing_3m_median_revenue * (
                1 + (
                    SELECT relative_decline_threshold
                    FROM account_health_parameters
                )
             )
         AND s.total_revenue - b.trailing_3m_median_revenue >= (
                SELECT minimum_eur_decline FROM account_health_parameters
             ) THEN 'Growing'
        ELSE 'Stable'
    END AS revenue_momentum_state
FROM eda_company_revenue_streaks s
LEFT JOIN baseline b USING (company_profile_id)
WHERE s.observation_month
      = (SELECT confirmed_end_month FROM analysis_parameters)
ORDER BY s.company_profile_id;

-- A single company-level source of truth for the lifecycle and momentum
-- language used in the presentation. "Healthy" now requires both continuity
-- and no material revenue-decline warning. It is still not a bank-account,
-- satisfaction, profitability, credit-quality, or contractual assessment.
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
         AND s.reactivated_active
            THEN 'Recovered / monitor'
        WHEN s.has_revenue_this_month
         AND m.revenue_momentum_state = 'Insufficient history'
            THEN 'Insufficient history'
        WHEN s.has_revenue_this_month
         AND m.revenue_momentum_state = 'Declining'
            THEN 'Watch - revenue declining'
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
    m.baseline_months,
    m.trailing_3m_median_revenue,
    m.trailing_3m_average_revenue,
    m.revenue_change_vs_trailing_median,
    m.revenue_change_vs_trailing_median_pct,
    m.revenue_momentum_state,
    l.first_revenue_month,
    l.last_revenue_month,
    l.inactive_months_at_cutoff,
    l.last_total_revenue AS last_observed_month_revenue,
    r.cumulative_total_revenue,
    COALESCE(r.is_top_10pct, FALSE) AS is_top_10pct,
    COALESCE(r.is_top_20pct, FALSE) AS is_top_20pct
FROM eda_company_revenue_streaks s
LEFT JOIN eda_company_revenue_momentum_at_cutoff m
    USING (company_profile_id)
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
        WHEN 'Watch - revenue declining' THEN 2
        WHEN 'Recovered / monitor' THEN 3
        WHEN 'Insufficient history' THEN 4
        WHEN 'At-risk' THEN 5
        WHEN 'Churned proxy' THEN 6
        ELSE 7
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
    WHEN 'Watch - revenue declining' THEN 2
    WHEN 'Recovered / monitor' THEN 3
    WHEN 'Insufficient history' THEN 4
    WHEN 'At-risk' THEN 5
    WHEN 'Churned proxy' THEN 6
    ELSE 7
END;

-- Threshold sensitivity: use this to show that the Watch result is not based
-- on a single arbitrary percentage choice.
CREATE OR REPLACE TABLE eda_revenue_momentum_threshold_sensitivity AS
WITH thresholds(relative_decline_threshold, minimum_eur_decline) AS (
    VALUES
        (0.20, 0.00), (0.30, 0.00), (0.40, 0.00),
        (0.20, 10.00), (0.30, 10.00), (0.40, 10.00)
),
eligible AS (
    SELECT
        m.*,
        r.is_top_20pct
    FROM eda_company_revenue_momentum_at_cutoff m
    LEFT JOIN eda_company_cumulative_revenue_rank r
        USING (company_profile_id)
    WHERE m.has_revenue_this_month
      AND m.continuously_active_since_activation
      AND m.baseline_months = 3
)
SELECT
    relative_decline_threshold,
    minimum_eur_decline,
    COUNT(*) AS eligible_continuously_active_companies,
    COUNT(*) FILTER (
        WHERE cutoff_month_revenue
                  <= trailing_3m_median_revenue
                     * (1 - relative_decline_threshold)
          AND trailing_3m_median_revenue - cutoff_month_revenue
                  >= minimum_eur_decline
    ) AS declining_companies,
    ROUND(
        100.0 * declining_companies
        / NULLIF(eligible_continuously_active_companies, 0),
        2
    ) AS declining_company_share_pct,
    COUNT(*) FILTER (WHERE is_top_20pct)
        AS eligible_top_20pct_companies,
    COUNT(*) FILTER (
        WHERE is_top_20pct
          AND cutoff_month_revenue
                  <= trailing_3m_median_revenue
                     * (1 - relative_decline_threshold)
          AND trailing_3m_median_revenue - cutoff_month_revenue
                  >= minimum_eur_decline
    ) AS declining_top_20pct_companies,
    ROUND(
        100.0 * declining_top_20pct_companies
        / NULLIF(eligible_top_20pct_companies, 0),
        2
    ) AS declining_top_20pct_company_share_pct
FROM eligible
CROSS JOIN thresholds
GROUP BY relative_decline_threshold, minimum_eur_decline
ORDER BY minimum_eur_decline, relative_decline_threshold;

-- Segment profile of the selected 30% + €10 Watch definition within the
-- cumulative high-value group. The summed median-to-April difference is an
-- observed monthly gap, not a forecast or causal opportunity estimate.
CREATE OR REPLACE TABLE eda_top20_revenue_momentum_by_segment AS
WITH eligible AS (
    SELECT *
    FROM eda_company_account_health_at_cutoff
    WHERE is_top_20pct
      AND has_revenue_this_month
      AND continuously_active_since_activation
      AND baseline_months = 3
),
aggregated AS (
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
        COUNT(*) AS companies_with_sufficient_history,
        COUNT(*) FILTER (
            WHERE account_health_state = 'Watch - revenue declining'
        ) AS declining_companies,
        SUM(cutoff_month_revenue) FILTER (
            WHERE account_health_state = 'Watch - revenue declining'
        ) AS declining_companies_april_revenue,
        SUM(trailing_3m_median_revenue) FILTER (
            WHERE account_health_state = 'Watch - revenue declining'
        ) AS declining_companies_baseline_revenue
    FROM eligible
    GROUP BY GROUPING SETS (
        (),
        (persona),
        (initial_subscription_group),
        (persona, initial_subscription_group)
    )
)
SELECT
    *,
    ROUND(
        100.0 * declining_companies
        / NULLIF(companies_with_sufficient_history, 0),
        2
    ) AS declining_company_share_pct,
    declining_companies_baseline_revenue - declining_companies_april_revenue
        AS observed_monthly_revenue_gap
FROM aggregated
ORDER BY segment_level, declining_companies DESC, persona,
         initial_subscription_group;

-- Transparent segment ranking for the presentation. Bar length can show share
-- of high-value revenue while the representation index distinguishes scalable
-- efficiency from segment size. No opaque composite score is used.
CREATE OR REPLACE TABLE eda_segment_opportunity_ranking AS
WITH ranked AS (
    SELECT
        segment_level,
        CASE
            WHEN segment_level = 'persona' THEN persona
            ELSE initial_subscription_group
        END AS segment_name,
        eligible_companies,
        top_20pct_companies,
        segment_revenue,
        segment_revenue / NULLIF(eligible_companies, 0)
            AS average_first3_full_month_revenue,
        segment_top_20pct_penetration_pct,
        share_of_all_top_20pct_revenue_pct,
        company_representation_index,
        ROW_NUMBER() OVER (
            PARTITION BY segment_level
            ORDER BY
                share_of_all_top_20pct_revenue_pct DESC,
                top_20pct_companies DESC,
                segment_name
        ) AS revenue_opportunity_rank
    FROM eda_first3_full_month_top20_revenue_by_segment
    WHERE segment_level IN ('persona', 'initial_plan')
)
SELECT *
FROM ranked
ORDER BY segment_level, revenue_opportunity_rank;

-- Fair current-health comparison. Companies activated by December have three
-- complete post-activation calendar months (January-March) before the April
-- cutoff. Restricting to this mature base removes the 60% insufficient-history
-- block that would otherwise dominate a full-population stacked chart.
CREATE OR REPLACE TABLE eda_comparable_account_health_by_segment AS
WITH mature_companies AS (
    SELECT *
    FROM eda_company_account_health_at_cutoff
    WHERE DATE_DIFF(
        'month',
        activation_month,
        (SELECT confirmed_end_month FROM analysis_parameters)
    ) >= 4
),
aggregated AS (
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
        SUM(cumulative_total_revenue) AS cumulative_revenue
    FROM mature_companies
    GROUP BY GROUPING SETS (
        (account_health_state),
        (account_health_state, persona),
        (account_health_state, initial_subscription_group),
        (account_health_state, persona, initial_subscription_group)
    )
)
SELECT
    *,
    SUM(companies) OVER (
        PARTITION BY segment_level, persona, initial_subscription_group
    ) AS comparable_segment_companies,
    ROUND(
        100.0 * companies / NULLIF(comparable_segment_companies, 0),
        2
    ) AS comparable_segment_company_share_pct
FROM aggregated
ORDER BY
    segment_level,
    persona,
    initial_subscription_group,
    CASE account_health_state
        WHEN 'Healthy revenue account' THEN 1
        WHEN 'Watch - revenue declining' THEN 2
        WHEN 'Recovered / monitor' THEN 3
        WHEN 'At-risk' THEN 4
        WHEN 'Churned proxy' THEN 5
        WHEN 'Never monetized' THEN 6
        ELSE 7
    END;
