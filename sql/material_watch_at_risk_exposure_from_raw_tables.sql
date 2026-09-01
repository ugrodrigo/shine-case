-- Rebuild the April 2026 Material Watch + At-risk revenue-exposure proxy
-- directly from the two original case tables: companies and revenue.
-- May is excluded because it is incomplete.

WITH params AS (
    SELECT
        DATE '2025-10-01' AS first_month,
        DATE '2026-04-01' AS cutoff_month
),
mature_companies AS (
    SELECT
        company_profile_id,
        DATE_TRUNC('month', activation_date)::DATE AS activation_month
    FROM companies
    WHERE activation_date IS NOT NULL
      -- Four calendar months of age at the April cutoff.
      AND DATE_DIFF(
              'month',
              DATE_TRUNC('month', activation_date)::DATE,
              (SELECT cutoff_month FROM params)
          ) >= 4
),
months AS (
    SELECT month::DATE AS revenue_month
    FROM params,
    GENERATE_SERIES(
        first_month,
        cutoff_month,
        INTERVAL '1 month'
    ) AS calendar(month)
),
company_months AS (
    SELECT
        c.company_profile_id,
        c.activation_month,
        m.revenue_month
    FROM mature_companies c
    CROSS JOIN months m
    WHERE m.revenue_month >= GREATEST(
        c.activation_month,
        (SELECT first_month FROM params)
    )
),
monthly_revenue AS (
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
    WHERE revenue_month <= (SELECT cutoff_month FROM params)
    GROUP BY 1, 2
),
history AS (
    SELECT
        cm.*,
        r.company_profile_id IS NOT NULL AS has_revenue,
        COALESCE(r.total_revenue, 0) AS total_revenue,
        MEDIAN(COALESCE(r.total_revenue, 0)) OVER (
            PARTITION BY cm.company_profile_id
            ORDER BY cm.revenue_month
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prior_3m_median,
        MIN(CASE WHEN r.company_profile_id IS NOT NULL
                 THEN cm.revenue_month END) OVER (
            PARTITION BY cm.company_profile_id
            ORDER BY cm.revenue_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS first_revenue_month,
        MAX(CASE WHEN r.company_profile_id IS NOT NULL
                 THEN cm.revenue_month END) OVER (
            PARTITION BY cm.company_profile_id
            ORDER BY cm.revenue_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS last_revenue_month
    FROM company_months cm
    LEFT JOIN monthly_revenue r USING (company_profile_id, revenue_month)
),
history_with_gaps AS (
    SELECT
        *,
        COALESCE(SUM(
            CASE WHEN NOT has_revenue AND first_revenue_month IS NOT NULL
                 THEN 1 ELSE 0 END
        ) OVER (
            PARTITION BY company_profile_id
            ORDER BY revenue_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ), 0) AS prior_post_revenue_gaps
    FROM history
),
last_observed_revenue AS (
    SELECT
        company_profile_id,
        ARG_MAX(total_revenue, revenue_month) AS last_month_revenue
    FROM monthly_revenue
    GROUP BY 1
),
april_snapshot AS (
    SELECT
        h.*,
        l.last_month_revenue,
        CASE
            WHEN h.has_revenue
             AND h.prior_post_revenue_gaps = 0
             AND h.prior_3m_median > 0
             AND h.total_revenue <= 0.70 * h.prior_3m_median
             AND h.prior_3m_median - h.total_revenue >= 10
                THEN 'Material Watch'
            WHEN NOT h.has_revenue
             AND h.last_revenue_month IS NOT NULL
             AND DATE_DIFF('month', h.last_revenue_month, h.revenue_month) < 3
                THEN 'At-risk'
        END AS health_state
    FROM history_with_gaps h
    LEFT JOIN last_observed_revenue l USING (company_profile_id)
    WHERE h.revenue_month = (SELECT cutoff_month FROM params)
),
exposure_by_company AS (
    SELECT
        company_profile_id,
        health_state,
        CASE
            WHEN health_state = 'Material Watch'
                THEN prior_3m_median - total_revenue
            WHEN health_state = 'At-risk'
                THEN last_month_revenue
        END AS monthly_revenue_exposure
    FROM april_snapshot
    WHERE health_state IS NOT NULL
),
summary AS (
    SELECT
        health_state,
        COUNT(*) AS companies,
        SUM(monthly_revenue_exposure) AS gross_monthly_exposure
    FROM exposure_by_company
    GROUP BY 1
),
mature_total AS (
    SELECT COUNT(*) AS mature_companies
    FROM mature_companies
),
final AS (
    SELECT
        s.health_state,
        s.companies,
        ROUND(
            100.0 * s.companies / m.mature_companies,
            1
        ) AS share_of_mature_companies_pct,
        ROUND(s.gross_monthly_exposure, 2) AS gross_monthly_exposure_eur,
        ROUND(s.gross_monthly_exposure * 0.10, 2) AS recovery_at_10pct_eur,
        ROUND(s.gross_monthly_exposure * 0.20, 2) AS recovery_at_20pct_eur
    FROM summary s
    CROSS JOIN mature_total m

    UNION ALL

    SELECT
        'TOTAL',
        SUM(s.companies),
        ROUND(
            100.0 * SUM(s.companies) / MAX(m.mature_companies),
            1
        ),
        ROUND(SUM(s.gross_monthly_exposure), 2),
        ROUND(SUM(s.gross_monthly_exposure) * 0.10, 2),
        ROUND(SUM(s.gross_monthly_exposure) * 0.20, 2)
    FROM summary s
    CROSS JOIN mature_total m
)
SELECT
    *
FROM final
ORDER BY CASE health_state
    WHEN 'Material Watch' THEN 1
    WHEN 'At-risk' THEN 2
    ELSE 3
END;
