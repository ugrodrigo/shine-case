-- Simple-query appendix for the raw-data memo.
-- Run from the project root with:
--     python scripts/run_query.py sql/simple_raw_memo_queries.sql
--
-- `companies` is the typed copy of the companies CSV.
-- `revenue_with_total` is the typed revenue CSV plus the four revenue columns.
-- These queries intentionally avoid the advanced cohort, health, concentration,
-- and equal-tenure modelling used elsewhere in the project.

-- ============================================================
-- QUERY 1: REVENUE BY PERSONA THROUGH THE CONFIRMED APRIL CUTOFF
-- ============================================================
SELECT
    c.persona,
    COUNT(DISTINCT r.company_profile_id) AS revenue_companies,
    ROUND(SUM(r.total_revenue), 2) AS total_revenue,
    ROUND(
        100.0 * SUM(r.total_revenue)
        / SUM(SUM(r.total_revenue)) OVER (),
        2
    ) AS revenue_share_pct,
    ROUND(
        SUM(r.total_revenue)
        / NULLIF(COUNT(DISTINCT r.company_profile_id), 0),
        2
    ) AS revenue_per_revenue_company
FROM companies c
JOIN revenue_with_total r
    ON c.company_profile_id = r.company_profile_id
WHERE r.revenue_month <= DATE '2026-04-01'
GROUP BY c.persona
ORDER BY total_revenue DESC;

-- ============================================================
-- QUERY 2: APRIL PERSONA SNAPSHOT
-- ============================================================
SELECT
    c.persona,
    COUNT(DISTINCT r.company_profile_id) AS revenue_companies,
    ROUND(SUM(r.total_revenue), 2) AS total_revenue,
    ROUND(
        100.0 * SUM(r.total_revenue)
        / SUM(SUM(r.total_revenue)) OVER (),
        2
    ) AS revenue_share_pct,
    ROUND(
        SUM(r.total_revenue)
        / NULLIF(COUNT(DISTINCT r.company_profile_id), 0),
        2
    ) AS revenue_per_revenue_company
FROM companies c
JOIN revenue_with_total r
    ON c.company_profile_id = r.company_profile_id
WHERE r.revenue_month = DATE '2026-04-01'
GROUP BY c.persona
ORDER BY total_revenue DESC;

-- ============================================================
-- QUERY 3: REVENUE BY INITIAL PLAN THROUGH APRIL
-- ============================================================
SELECT
    c.initial_subscription_group,
    COUNT(DISTINCT r.company_profile_id) AS revenue_companies,
    ROUND(SUM(r.total_revenue), 2) AS total_revenue,
    ROUND(
        100.0 * SUM(r.total_revenue)
        / SUM(SUM(r.total_revenue)) OVER (),
        2
    ) AS revenue_share_pct,
    ROUND(
        SUM(r.total_revenue)
        / NULLIF(COUNT(DISTINCT r.company_profile_id), 0),
        2
    ) AS revenue_per_revenue_company
FROM companies c
JOIN revenue_with_total r
    ON c.company_profile_id = r.company_profile_id
WHERE r.revenue_month <= DATE '2026-04-01'
GROUP BY c.initial_subscription_group
ORDER BY total_revenue DESC;

-- ============================================================
-- QUERY 4: APRIL INITIAL-PLAN SNAPSHOT
-- ============================================================
SELECT
    c.initial_subscription_group,
    COUNT(DISTINCT r.company_profile_id) AS revenue_companies,
    ROUND(SUM(r.total_revenue), 2) AS total_revenue,
    ROUND(
        100.0 * SUM(r.total_revenue)
        / SUM(SUM(r.total_revenue)) OVER (),
        2
    ) AS revenue_share_pct,
    ROUND(
        SUM(r.total_revenue)
        / NULLIF(COUNT(DISTINCT r.company_profile_id), 0),
        2
    ) AS revenue_per_revenue_company
FROM companies c
JOIN revenue_with_total r
    ON c.company_profile_id = r.company_profile_id
WHERE r.revenue_month = DATE '2026-04-01'
GROUP BY c.initial_subscription_group
ORDER BY total_revenue DESC;

-- ============================================================
-- QUERY 5: MONTHLY REVENUE; MAY IS SHOWN BUT LABELLED PROVISIONAL
-- ============================================================
SELECT
    revenue_month,
    CASE
        WHEN revenue_month <= DATE '2026-04-01' THEN 'confirmed analysis'
        ELSE 'provisional sensitivity'
    END AS analysis_status,
    COUNT(DISTINCT company_profile_id) AS revenue_companies,
    ROUND(SUM(total_revenue), 2) AS total_revenue
FROM revenue_with_total
GROUP BY revenue_month
ORDER BY revenue_month;

-- ============================================================
-- QUERY 6: APRIL REVENUE MIX
-- ============================================================
SELECT
    ROUND(SUM(subscription_revenue), 2) AS subscription_revenue,
    ROUND(SUM(interchange_revenue), 2) AS interchange_revenue,
    ROUND(SUM(banking_fees), 2) AS banking_fees,
    ROUND(SUM(deposit_interest_revenue), 2) AS deposit_interest_revenue,
    ROUND(SUM(total_revenue), 2) AS total_revenue
FROM revenue_with_total
WHERE revenue_month = DATE '2026-04-01';

-- ============================================================
-- QUERY 7: SIMPLE MARCH-TO-APRIL REVENUE DECLINE CHECK
-- ============================================================
-- This is an early-warning screen, not a churn definition. It only compares
-- two months and does not adjust for customer age or past volatility.
WITH company_revenue AS (
    SELECT
        company_profile_id,
        SUM(CASE
            WHEN revenue_month = DATE '2026-03-01' THEN total_revenue
            ELSE 0
        END) AS march_revenue,
        SUM(CASE
            WHEN revenue_month = DATE '2026-04-01' THEN total_revenue
            ELSE 0
        END) AS april_revenue
    FROM revenue_with_total
    WHERE revenue_month IN (DATE '2026-03-01', DATE '2026-04-01')
    GROUP BY company_profile_id
)
SELECT
    COUNT(*) FILTER (
        WHERE march_revenue > 0 AND april_revenue > 0
    ) AS active_in_both_months,
    COUNT(*) FILTER (
        WHERE march_revenue > 0
          AND april_revenue > 0
          AND april_revenue <= 0.70 * march_revenue
          AND march_revenue - april_revenue >= 10
    ) AS material_decline_companies,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE march_revenue > 0
              AND april_revenue > 0
              AND april_revenue <= 0.70 * march_revenue
              AND march_revenue - april_revenue >= 10
        ) / NULLIF(COUNT(*) FILTER (
            WHERE march_revenue > 0 AND april_revenue > 0
        ), 0),
        2
    ) AS material_decline_share_pct,
    COUNT(*) FILTER (
        WHERE march_revenue > 0 AND april_revenue = 0
    ) AS first_observed_gap_in_april
FROM company_revenue;

-- ============================================================
-- QUERY 8: THE USER'S ALL-AVAILABLE-MONTHS VIEW, INCLUDING MAY
-- ============================================================
-- Keep this as a sensitivity. It is valid raw cumulative revenue, but older
-- companies have more months to contribute and May has incomplete signup data.
SELECT
    c.persona,
    ROUND(SUM(r.total_revenue), 2) AS total_revenue,
    SUM(r.total_revenue) / SUM(SUM(r.total_revenue)) OVER () AS revenue_share,
    SUM(r.total_revenue)
        / NULLIF(COUNT(DISTINCT r.company_profile_id), 0)
        AS revenue_per_revenue_company
FROM companies c
JOIN revenue_with_total r
    ON c.company_profile_id = r.company_profile_id
GROUP BY c.persona
ORDER BY total_revenue DESC;

-- ============================================================
-- WHERE TO FIND THE MORE RIGOROUS VERSIONS
-- ============================================================
-- Equal-tenure segment ranking and top-20 concentration:
--     sql/revenue_concentration_analysis.sql
-- Presentation ranking and account-health states:
--     sql/presentation_kpis.sql
-- Cohort lifecycle states:
--     sql/cohort_state_analysis.sql
-- Revenue streaks and recovery persistence:
--     sql/streak_analysis.sql
-- Funnel, inactivity, revenue trends, and observed-LTV diagnostics:
--     sql/kpi_deep_dive.sql
