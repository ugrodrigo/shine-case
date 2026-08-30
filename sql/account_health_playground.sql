-- Account-health momentum playground
-- Run with: python scripts/run_query.py sql/account_health_playground.sql
--
-- This sensitivity tests revenue-decline thresholds among companies that are
-- revenue-active at the April cutoff. The baseline is the median of the three
-- most recent complete calendar months before the cutoff, excluding the
-- activation month because it may represent only a partial month of exposure.

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
        COUNT(*) FILTER (WHERE recency_rank <= 3) AS baseline_months,
        MEDIAN(total_revenue) FILTER (WHERE recency_rank <= 3)
            AS trailing_3m_median_revenue,
        AVG(total_revenue) FILTER (WHERE recency_rank <= 3)
            AS trailing_3m_average_revenue
    FROM prior_complete_months
    GROUP BY company_profile_id
),
active_at_cutoff AS (
    SELECT
        s.company_profile_id,
        s.continuously_active_since_activation,
        s.total_revenue AS cutoff_month_revenue,
        COALESCE(b.baseline_months, 0) AS baseline_months,
        b.trailing_3m_median_revenue,
        b.trailing_3m_average_revenue,
        r.is_top_20pct
    FROM eda_company_revenue_streaks s
    LEFT JOIN baseline b USING (company_profile_id)
    LEFT JOIN eda_company_cumulative_revenue_rank r USING (company_profile_id)
    WHERE s.observation_month
              = (SELECT confirmed_end_month FROM analysis_parameters)
      AND s.has_revenue_this_month
),
thresholds(relative_decline_threshold, minimum_eur_decline) AS (
    VALUES
        (0.20, 0.00), (0.30, 0.00), (0.40, 0.00),
        (0.20, 10.00), (0.30, 10.00), (0.40, 10.00)
)
SELECT
    relative_decline_threshold,
    minimum_eur_decline,
    COUNT(*) FILTER (
        WHERE continuously_active_since_activation AND is_top_20pct
    ) AS top20_continuously_active,
    COUNT(*) FILTER (
        WHERE continuously_active_since_activation
          AND is_top_20pct
          AND baseline_months = 3
    ) AS top20_with_sufficient_history,
    COUNT(*) FILTER (
        WHERE continuously_active_since_activation
          AND is_top_20pct
          AND baseline_months = 3
          AND cutoff_month_revenue
                <= trailing_3m_median_revenue
                   * (1 - relative_decline_threshold)
          AND trailing_3m_median_revenue - cutoff_month_revenue
                >= minimum_eur_decline
    ) AS top20_declining,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE continuously_active_since_activation
              AND is_top_20pct
              AND baseline_months = 3
              AND cutoff_month_revenue
                    <= trailing_3m_median_revenue
                       * (1 - relative_decline_threshold)
              AND trailing_3m_median_revenue - cutoff_month_revenue
                    >= minimum_eur_decline
        ) / NULLIF(COUNT(*) FILTER (
            WHERE continuously_active_since_activation
              AND is_top_20pct
              AND baseline_months = 3
        ), 0),
        2
    ) AS declining_share_of_eligible_top20_pct
FROM active_at_cutoff
CROSS JOIN thresholds
GROUP BY relative_decline_threshold, minimum_eur_decline
ORDER BY minimum_eur_decline, relative_decline_threshold;

-- Useful variations:
-- 1. Remove `is_top_20pct` filters to assess the full active population.
-- 2. Replace MEDIAN with AVG to test sensitivity to one-off revenue spikes.
-- 3. Change the €10 materiality floor after reviewing revenue economics.
