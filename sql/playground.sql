-- DuckDB playground for the Shine case
-- Edit this file, save it, then run:
--     python scripts/run_query.py
--
-- Available tables:
--   companies
--   revenue
--   revenue_with_total
--
-- Tip: start with a small LIMIT while exploring.

-- SELECT
--     r.revenue_month,
--     c.persona,
--     COUNT(DISTINCT r.company_profile_id) AS revenue_companies,
--     ROUND(SUM(r.total_revenue), 2) AS total_revenue,
--     ROUND(
--         SUM(r.total_revenue)
--         / NULLIF(COUNT(DISTINCT r.company_profile_id), 0),
--         2
--     ) AS revenue_per_revenue_company
-- FROM revenue_with_total r
-- JOIN companies c USING (company_profile_id)
-- WHERE r.revenue_month BETWEEN DATE '2026-01-01' AND DATE '2026-04-01'
-- GROUP BY r.revenue_month, c.persona
-- ORDER BY r.revenue_month, total_revenue DESC;

-- SELECT 
--     c.persona,
--     ROUND(SUM(r.total_revenue), 2) AS total_revenue,
--     ROUND(SUM(r.total_revenue) / SUM(SUM(r.total_revenue)) OVER (), 4) AS revenue_share,
--     ROUND(SUM(r.total_revenue) / NULLIF(COUNT(DISTINCT r.company_profile_id), 0), 2) AS revenue_per_revenue_company
-- FROM companies c
-- JOIN revenue_with_total r 
--     ON c.company_profile_id = r.company_profile_id
-- WHERE 
--     r.revenue_month < DATE '2026-05-01'
--     AND c.company_signup_at < DATE '2026-05-01'
-- GROUP BY c.persona    
-- ORDER BY total_revenue DESC;



SELECT 
    c.initial_subscription_group,
    ROUND(SUM(r.subscription_revenue), 2)/COUNT(DISTINCT r.company_profile_id) AS subscription_revenue,
    ROUND(SUM(r.interchange_revenue), 2)/COUNT(DISTINCT r.company_profile_id) AS interchange_revenue,
    ROUND(SUM(r.banking_fees), 2)/COUNT(DISTINCT r.company_profile_id) AS banking_fees,
    ROUND(SUM(r.deposit_interest_revenue), 2)/COUNT(DISTINCT r.company_profile_id) AS deposit_interest_revenue
FROM companies c
JOIN revenue_with_total r 
    ON c.company_profile_id = r.company_profile_id
WHERE 
    r.revenue_month < DATE '2026-05-01'
    AND c.company_signup_at < DATE '2026-05-01'
GROUP BY 1    
ORDER BY 5 desc;

-- Other ideas to try (uncomment one at a time):

-- Inspect the raw company table:
-- SELECT * FROM companies

-- Inspect the raw revenue table:
-- SELECT * FROM revenue_with_total LIMIT 20;

-- Focus on a persona:
-- SELECT *
-- FROM revenue_with_total r
-- JOIN companies c USING (company_profile_id)
-- WHERE c.persona = 'Consultant'
-- ORDER BY total_revenue DESC
-- LIMIT 50;

-- Change the latest-month segment from persona to initial plan:
-- SELECT
--     c.initial_subscription_group,
--     COUNT(DISTINCT r.company_profile_id) AS companies,
--     ROUND(SUM(r.total_revenue), 2) AS revenue
-- FROM revenue_with_total r
-- JOIN companies c USING (company_profile_id)
-- WHERE r.revenue_month = DATE '2026-04-01'
-- GROUP BY c.initial_subscription_group
-- ORDER BY revenue DESC;
