-- Cohort-analysis playground
-- Run with: python scripts/run_query.py sql/cohort_playground.sql
--
-- Cohorts use activation_month. Customer age is months_since_activation.
-- May is excluded through the confirmed April cutoff.

-- Compare cohorts at the SAME customer age. Change `3` to 1, 2, 4, etc.
SELECT
    activation_month,
    activated_cohort_size,
    active_share_pct,
    at_risk_share_pct,
    churned_proxy_share_pct,
    never_monetized_share_pct,
    ROUND(revenue_per_original_activated_company, 2)
        AS monthly_revenue_per_activated_company
FROM eda_cohort_state_matrix_by_segment
WHERE segment_level = 'overall'
  AND months_since_activation = 3
ORDER BY activation_month;

-- Useful variations:
--
-- 1. Compare initial plans at age 3:
--    change segment_level to 'initial_plan' and add
--    initial_subscription_group to SELECT.
--
-- 2. Compare personas at age 3:
--    change segment_level to 'persona' and add persona to SELECT.
--
-- 3. Follow one cohort over time:
--    remove the age filter and add:
--    AND activation_month = DATE '2025-11-01'
--
-- 4. Inspect state transitions such as recovery from At-risk:
-- SELECT
--     activation_month,
--     months_since_activation,
--     prior_revenue_lifecycle_state,
--     revenue_lifecycle_state,
--     companies,
--     transition_rate_from_prior_state_pct
-- FROM eda_cohort_state_transitions_by_segment
-- WHERE segment_level = 'overall'
--   AND prior_revenue_lifecycle_state = 'At-risk'
-- ORDER BY activation_month, months_since_activation,
--          revenue_lifecycle_state;
