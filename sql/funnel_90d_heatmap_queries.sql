-- Query 1: overall 90-day funnel
WITH funnel AS (
    SELECT
        validation_date BETWEEN company_signup_at::DATE
                            AND company_signup_at::DATE + INTERVAL 90 DAY
            AS validated_90d,
        validation_date BETWEEN company_signup_at::DATE
                            AND company_signup_at::DATE + INTERVAL 90 DAY
        AND activation_date BETWEEN validation_date
                                AND company_signup_at::DATE + INTERVAL 90 DAY
            AS activated_90d
    FROM companies
    WHERE company_signup_at >= DATE '2025-10-01'
      AND company_signup_at <  DATE '2026-01-31'
)
SELECT
    COUNT(*) AS n,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE validated_90d) / COUNT(*),
        1
    ) AS signup_to_validation_90d_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE activated_90d)
        / NULLIF(COUNT(*) FILTER (WHERE validated_90d), 0),
        1
    ) AS validation_to_activation_90d_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE activated_90d) / COUNT(*),
        1
    ) AS signup_to_activation_90d_pct
FROM funnel;


-- Query 2: 90-day funnel by persona
WITH funnel AS (
    SELECT
        persona,
        validation_date BETWEEN company_signup_at::DATE
                            AND company_signup_at::DATE + INTERVAL 90 DAY
            AS validated_90d,
        validation_date BETWEEN company_signup_at::DATE
                            AND company_signup_at::DATE + INTERVAL 90 DAY
        AND activation_date BETWEEN validation_date
                                AND company_signup_at::DATE + INTERVAL 90 DAY
            AS activated_90d
    FROM companies
    WHERE company_signup_at >= DATE '2025-10-01'
      AND company_signup_at <  DATE '2026-01-31'
)
SELECT
    persona,
    COUNT(*) AS n,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE validated_90d) / COUNT(*),
        1
    ) AS signup_to_validation_90d_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE activated_90d)
        / NULLIF(COUNT(*) FILTER (WHERE validated_90d), 0),
        1
    ) AS validation_to_activation_90d_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE activated_90d) / COUNT(*),
        1
    ) AS signup_to_activation_90d_pct
FROM funnel
GROUP BY persona
ORDER BY signup_to_activation_90d_pct DESC;


-- Query 3: 90-day funnel by initial plan
WITH funnel AS (
    SELECT
        initial_subscription_group,
        validation_date BETWEEN company_signup_at::DATE
                            AND company_signup_at::DATE + INTERVAL 90 DAY
            AS validated_90d,
        validation_date BETWEEN company_signup_at::DATE
                            AND company_signup_at::DATE + INTERVAL 90 DAY
        AND activation_date BETWEEN validation_date
                                AND company_signup_at::DATE + INTERVAL 90 DAY
            AS activated_90d
    FROM companies
    WHERE company_signup_at >= DATE '2025-10-01'
      AND company_signup_at <  DATE '2026-01-31'
)
SELECT
    initial_subscription_group,
    COUNT(*) AS n,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE validated_90d) / COUNT(*),
        1
    ) AS signup_to_validation_90d_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE activated_90d)
        / NULLIF(COUNT(*) FILTER (WHERE validated_90d), 0),
        1
    ) AS validation_to_activation_90d_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE activated_90d) / COUNT(*),
        1
    ) AS signup_to_activation_90d_pct
FROM funnel
GROUP BY initial_subscription_group
ORDER BY signup_to_activation_90d_pct DESC;
