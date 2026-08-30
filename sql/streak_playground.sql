-- Revenue-streak playground
-- Run with: python scripts/run_query.py sql/streak_playground.sql

-- Rank personas at the same customer age. Change the minimum sample or switch
-- segment_level to 'initial_plan' and select initial_subscription_group.
SELECT
    persona,
    companies,
    active_share_pct,
    continuously_active_share_pct,
    reactivated_active_share_pct,
    average_current_streak_among_active,
    ROUND(monthly_revenue_per_original_activated_company, 2)
        AS monthly_revenue_per_activated_company
FROM eda_age3_streak_scorecard
WHERE segment_level = 'persona'
  AND companies >= 100
ORDER BY continuously_active_share_pct DESC;

-- To test whether continuity predicts next-month activity, replace the query
-- above with this one:
--
-- SELECT
--     months_since_activation,
--     current_active_streak_months,
--     eligible_active_company_months,
--     next_month_active_rate_pct
-- FROM eda_streak_next_month_persistence_by_segment
-- WHERE segment_level = 'overall'
-- ORDER BY months_since_activation, current_active_streak_months;
