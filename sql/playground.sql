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



-- SELECT
--     ROUND(AVG(
--         subscription_revenue
--       + interchange_revenue
--       + banking_fees
--       + deposit_interest_revenue
--     ), 2) AS avg_total_revenue_per_company_per_month
-- FROM revenue r
-- JOIN companies c
--     ON r.company_profile_id = c.company_profile_id
-- WHERE 
--     r.revenue_month < DATE '2026-05-01'
--     AND c.company_signup_at < DATE '2026-05-01';


-- SELECT
--     COUNT(*) AS validated_companies,
--     COUNT(*) FILTER (
--         WHERE activation_date IS NOT NULL
--     ) AS activated,
--     COUNT(*) FILTER (
--         WHERE activation_date IS NOT NULL
--     ) / COUNT(*) AS activation_rate
--     FROM companies
-- WHERE validation_date BETWEEN DATE '2025-10-01'
--                           AND DATE '2026-04-30';

-- SELECT
--     -- signup → validation
--     COUNT(*) FILTER (WHERE validation_date IS NOT NULL)::DECIMAL
--         / COUNT(*) AS signup_to_validation_rate,

--     -- validation → activation
--     COUNT(*) FILTER (WHERE activation_date IS NOT NULL)::DECIMAL
--         / COUNT(*) FILTER (WHERE validation_date IS NOT NULL) AS validation_to_activation_rate,

--     -- signup → activation (overall)
--     COUNT(*) FILTER (WHERE activation_date IS NOT NULL)::DECIMAL
--         / COUNT(*) AS signup_to_activation_rate

-- FROM companies
-- WHERE company_signup_at BETWEEN DATE '2025-10-01'
--                            AND DATE '2026-04-30'
-- ORDER BY 3 desc;

-- SELECT
--     persona,

--     -- signup → validation
--     COUNT(*) FILTER (WHERE validation_date IS NOT NULL)::DECIMAL
--         / COUNT(*) AS signup_to_validation_rate,

--     -- validation → activation
--     COUNT(*) FILTER (WHERE activation_date IS NOT NULL)::DECIMAL
--         / COUNT(*) FILTER (WHERE validation_date IS NOT NULL) AS validation_to_activation_rate,

--     -- signup → activation (overall)
--     COUNT(*) FILTER (WHERE activation_date IS NOT NULL)::DECIMAL
--         / COUNT(*) AS signup_to_activation_rate

-- FROM companies
-- WHERE company_signup_at BETWEEN DATE '2025-10-01'
--                            AND DATE '2026-04-30'
-- GROUP BY persona
-- ORDER BY 4 desc;


-- SELECT
--     initial_subscription_group,

--     -- signup → validation
--     COUNT(*) FILTER (WHERE validation_date IS NOT NULL)::DECIMAL
--         / COUNT(*) AS signup_to_validation_rate,

--     -- validation → activation
--     COUNT(*) FILTER (WHERE activation_date IS NOT NULL)::DECIMAL
--         / COUNT(*) FILTER (WHERE validation_date IS NOT NULL) AS validation_to_activation_rate,

--     -- signup → activation (overall)
--     COUNT(*) FILTER (WHERE activation_date IS NOT NULL)::DECIMAL
--         / COUNT(*) AS signup_to_activation_rate

-- FROM companies
-- WHERE company_signup_at BETWEEN DATE '2025-10-01'
--                            AND DATE '2026-04-30'
-- GROUP BY 1
-- ORDER BY 4 desc;



-- SELECT
--     COUNT(*) AS validated_companies,
--     COUNT(*) FILTER (
--         WHERE activation_date IS NOT NULL
--     ) AS activated,
--     COUNT(*) FILTER (
--         WHERE activation_date IS NOT NULL
--     ) / COUNT(*) AS activation_rate,
--     (
--         SELECT ROUND(AVG(
--             subscription_revenue
--           + interchange_revenue
--           + banking_fees
--           + deposit_interest_revenue
--         ), 2)
--         FROM revenue r
--         JOIN companies c2
--             ON r.company_profile_id = c2.company_profile_id
--         WHERE 
--             r.revenue_month < DATE '2026-05-01'
--             AND c2.company_signup_at < DATE '2026-05-01'
--     ) AS avg_total_revenue_per_company_per_month,
--     (
--         SELECT COUNT(*)::DECIMAL
--                / COUNT(DISTINCT DATE_TRUNC('month', validation_date))
--         FROM companies
--         WHERE validation_date BETWEEN DATE '2025-10-01'
--                                  AND DATE '2026-04-30'
--     ) AS validated_companies_per_month
-- FROM companies c
-- WHERE validation_date BETWEEN DATE '2025-10-01'
--                           AND DATE '2026-04-30';



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


-- GROSS MONTHLY REVENUE EXPOSURE AT THE APRIL 2026 CUTOFF
-- Uses only the two original tables: companies and revenue.
-- May is excluded because it is incomplete.
WITH mature_companies AS (
    -- Keep companies activated by December 2025. This gives every company
    -- three complete comparison months (January-March) before April.
    SELECT
        company_profile_id,
        DATE_TRUNC('month', activation_date)::DATE AS activation_month
    FROM companies
    WHERE activation_date IS NOT NULL
      AND DATE_DIFF(
              'month',
              DATE_TRUNC('month', activation_date)::DATE,
              DATE '2026-04-01'
          ) >= 4
),
monthly_revenue AS (
    -- Build one total-revenue value per company and month by adding the four
    -- revenue components from the original revenue table.
    SELECT
        company_profile_id,
        revenue_month,
        SUM(
            subscription_revenue
            + interchange_revenue
            + banking_fees
            + deposit_interest_revenue
        ) AS total_revenue
    FROM revenue
    WHERE revenue_month <= DATE '2026-04-01'
    GROUP BY 1, 2
),
prior_3m_baseline AS (
    -- Treat a missing January, February, or March row as EUR 0, then take the
    -- median. The median is the company's recent "normal" monthly revenue.
    SELECT
        c.company_profile_id,
        MEDIAN(COALESCE(r.total_revenue, 0)) AS prior_3m_median
    FROM mature_companies c
    CROSS JOIN (
        VALUES
            (DATE '2026-01-01'),
            (DATE '2026-02-01'),
            (DATE '2026-03-01')
    ) AS baseline(revenue_month)
    LEFT JOIN monthly_revenue r
        ON c.company_profile_id = r.company_profile_id
       AND baseline.revenue_month = r.revenue_month
    GROUP BY 1
),
company_history AS (
    -- Create the inputs required for classification:
    --   * April revenue;
    --   * first and last observed revenue months;
    --   * revenue in the last observed month; and
    --   * the number of revenue-producing months.
    SELECT
        c.company_profile_id,
        b.prior_3m_median,
        MIN(r.revenue_month) AS first_revenue_month,
        MAX(r.revenue_month) AS last_revenue_month,
        ARG_MAX(r.total_revenue, r.revenue_month) AS last_month_revenue,
        COUNT(r.revenue_month) AS revenue_months_observed,
        COUNT(*) FILTER (
            WHERE r.revenue_month = DATE '2026-04-01'
        ) AS has_april_revenue,
        COALESCE(SUM(r.total_revenue) FILTER (
            WHERE r.revenue_month = DATE '2026-04-01'
        ), 0) AS april_revenue
    FROM mature_companies c
    JOIN prior_3m_baseline b USING (company_profile_id)
    LEFT JOIN monthly_revenue r
        ON c.company_profile_id = r.company_profile_id
       AND r.revenue_month >= GREATEST(
               c.activation_month,
               DATE '2025-10-01'
           )
    GROUP BY 1, 2
),
classified AS (
    -- Material Watch:
    --   still has April revenue, has no earlier gap after monetising,
    --   and April is both at least 30% and EUR 10 below the prior median.
    --
    -- At-risk:
    --   had revenue previously, has no April row, and its last revenue was
    --   only one or two months ago. Three or more months would be Churned proxy.
    SELECT
        *,
        CASE
            WHEN has_april_revenue = 1
             -- Observed months must equal all months from first revenue to
             -- April; otherwise the account recovered from an earlier gap.
             AND revenue_months_observed
                    = DATE_DIFF(
                          'month',
                          first_revenue_month,
                          DATE '2026-04-01'
                      ) + 1
             AND prior_3m_median > 0
             AND april_revenue <= prior_3m_median * 0.70
             AND prior_3m_median - april_revenue >= 10
                THEN 'Material Watch'
            WHEN has_april_revenue = 0
             AND last_revenue_month IS NOT NULL
             AND DATE_DIFF(
                     'month',
                     last_revenue_month,
                     DATE '2026-04-01'
                 ) < 3
                THEN 'At-risk'
        END AS health_state
    FROM company_history
),
exposure AS (
    -- Exposure is calculated differently for the two warning states:
    --   Material Watch = prior 3-month median - April revenue.
    --   At-risk       = revenue in the last observed month.
    -- This is a gross exposure proxy, not guaranteed lost or recoverable money.
    SELECT
        health_state,
        CASE
            WHEN health_state = 'Material Watch'
                THEN prior_3m_median - april_revenue
            WHEN health_state = 'At-risk'
                THEN last_month_revenue
        END AS gross_monthly_exposure
    FROM classified
    WHERE health_state IS NOT NULL
)
-- Add every company-level exposure to obtain the EUR 51.1k gross proxy.
-- The 10% and 20% columns are hypothetical recovery scenarios, not forecasts.
SELECT
    COUNT(*) AS companies,
    ROUND(SUM(gross_monthly_exposure), 2) AS gross_revenue_exposure_eur,
    ROUND(SUM(gross_monthly_exposure) * 0.10, 2) AS recovery_at_10pct_eur,
    ROUND(SUM(gross_monthly_exposure) * 0.20, 2) AS recovery_at_20pct_eur
FROM exposure;
