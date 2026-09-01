-- Illustrative revenue impact of improving 90-day post-KYB activation.
-- The 5 pp and 10 pp uplifts are scenarios to test, not historical results.

WITH validated_volume AS (
    SELECT
        persona,
        COUNT(*) / 6.0 AS validated_companies_per_month
    FROM companies
    WHERE validation_date >= DATE '2025-10-01'
      AND validation_date < DATE '2026-04-01'
    GROUP BY persona
),
april_revenue AS (
    SELECT
        c.persona,
        SUM(r.total_revenue)
            / COUNT(DISTINCT r.company_profile_id)
            AS april_revenue_per_company
    FROM companies c
    JOIN revenue_with_total r
      ON c.company_profile_id = r.company_profile_id
    WHERE r.revenue_month = DATE '2026-04-01'
    GROUP BY c.persona
),
scenarios(uplift_percentage_points) AS (
    VALUES (5.0), (10.0)
)
SELECT
    s.uplift_percentage_points AS activation_uplift_pp,
    ROUND(
        SUM(v.validated_companies_per_month)
            * s.uplift_percentage_points / 100,
        0
    ) AS extra_activations_per_monthly_cohort,
    ROUND(
        SUM(
            v.validated_companies_per_month
                * a.april_revenue_per_company
        ) * s.uplift_percentage_points / 100,
        0
    ) AS monthly_revenue_from_one_matured_cohort,
    ROUND(
        3 * SUM(
            v.validated_companies_per_month
                * a.april_revenue_per_company
        ) * s.uplift_percentage_points / 100,
        0
    ) AS monthly_revenue_after_three_matured_cohorts
FROM validated_volume v
JOIN april_revenue a USING (persona)
CROSS JOIN scenarios s
GROUP BY s.uplift_percentage_points
ORDER BY s.uplift_percentage_points;
