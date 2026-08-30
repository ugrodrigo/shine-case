-- Revenue-concentration playground
-- Run with: python scripts/run_query.py sql/concentration_playground.sql

-- Profile personas in the preferred top 20% revenue group.
-- This ranks companies on ages 1-3: their first three complete calendar
-- months after activation. Age 0 is excluded because the source is monthly
-- and cannot split activation-month revenue at the activation date.
SELECT
    persona,
    eligible_companies,
    top_20pct_companies,
    segment_top_20pct_penetration_pct,
    top_20pct_company_mix_pct,
    base_company_mix_pct,
    company_representation_index,
    share_of_all_top_20pct_revenue_pct
FROM eda_first3_full_month_top20_revenue_by_segment
WHERE segment_level = 'persona'
ORDER BY top_20pct_companies DESC;

-- Useful variations:
--
-- 1. Replace 'persona' with 'initial_plan' and select
--    initial_subscription_group instead of persona.
--
-- 2. Use eda_age3_top20_revenue_by_segment for the activation-month-inclusive
--    sensitivity (ages 0-3).
--
-- 3. Headline summary:
--    SELECT * FROM eda_first3_full_month_top20_revenue_summary;
--
-- 4. Cumulative revenue-type concentration (not tenure-controlled):
--    SELECT * FROM eda_top20_revenue_by_type;
--
-- 5. Switch back to eda_top10_revenue_companies_by_segment if you want the
--    original top-decile appendix.
--
-- 6. Test Pareto thresholds:
--    SELECT * FROM eda_revenue_concentration_curve;
--    SELECT * FROM eda_age3_revenue_concentration_curve;
