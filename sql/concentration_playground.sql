-- Revenue-concentration playground
-- Run with: python run_query.py sql/concentration_playground.sql

-- Profile personas in the cumulative top 20% revenue group.
SELECT
    persona,
    revenue_companies,
    top_20pct_companies,
    segment_top_20pct_penetration_pct,
    top_20pct_company_mix_pct,
    base_revenue_company_mix_pct,
    company_representation_index,
    top_20pct_share_of_segment_revenue_pct,
    share_of_all_top_20pct_revenue_pct
FROM eda_top20_revenue_companies_by_segment
WHERE segment_level = 'persona'
ORDER BY top_20pct_companies DESC;

-- Useful variations:
--
-- 1. Replace 'persona' with 'initial_plan' and select
--    initial_subscription_group instead of persona.
--
-- 2. Use eda_age3_top20_revenue_by_segment for the preferred tenure-controlled
--    version. Its population columns are named eligible_companies and
--    base_company_mix_pct.
--
-- 3. Headline summary:
--    SELECT * FROM eda_top20_revenue_concentration_summary;
--
-- 4. Revenue-type concentration:
--    SELECT * FROM eda_top20_revenue_by_type;
--
-- 5. Switch back to eda_top10_revenue_companies_by_segment if you want the
--    original top-decile appendix.
--
-- 6. Test Pareto thresholds:
--    SELECT * FROM eda_revenue_concentration_curve;
--    SELECT * FROM eda_age3_revenue_concentration_curve;
