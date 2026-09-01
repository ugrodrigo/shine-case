-- Diagnostic only: why does the initial Free plan convert less often from
-- validation to activation within 90 days? This cannot identify causality,
-- but it checks timing, closure, and persona-mix explanations.

WITH base AS (
    SELECT
        company_profile_id,
        persona,
        initial_subscription_group,
        company_signup_at::DATE AS signup_date,
        validation_date,
        activation_date,
        closed_date,
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
),
plan_summary AS (
    SELECT
        initial_subscription_group AS segment,
        COUNT(*) FILTER (WHERE validated_90d) AS validated,
        COUNT(*) FILTER (WHERE activated_90d) AS activated,
        ROUND(
            100.0 * activated
            / NULLIF(validated, 0),
            1
        ) AS validation_to_activation_90d_pct,
        ROUND(
            MEDIAN(DATE_DIFF('day', validation_date, activation_date))
                FILTER (WHERE activated_90d),
            1
        ) AS median_validation_to_activation_days,
        ROUND(
            100.0 * COUNT(*) FILTER (
                WHERE validated_90d
                  AND NOT activated_90d
                  AND closed_date BETWEEN validation_date
                                      AND signup_date + INTERVAL 90 DAY
            ) / NULLIF(COUNT(*) FILTER (WHERE validated_90d), 0),
            1
        ) AS validated_then_closed_without_activation_pct
    FROM base
    GROUP BY 1
)
SELECT *
FROM plan_summary
ORDER BY validation_to_activation_90d_pct DESC;

-- The second result is the persona-level check.
-- It tests whether Free is weak inside the same persona, rather than only
-- because Free happens to contain a different mix of personas.
WITH base AS (
    SELECT
        persona,
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
    persona,
    COUNT(*) FILTER (
        WHERE validated_90d AND initial_subscription_group = 'free'
    ) AS free_validated,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE activated_90d AND initial_subscription_group = 'free'
        ) / NULLIF(free_validated, 0),
        1
    ) AS free_validation_to_activation_pct,
    COUNT(*) FILTER (
        WHERE validated_90d AND initial_subscription_group <> 'free'
    ) AS paid_validated,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE activated_90d AND initial_subscription_group <> 'free'
        ) / NULLIF(paid_validated, 0),
        1
    ) AS paid_validation_to_activation_pct
FROM base
GROUP BY 1
HAVING free_validated >= 100 AND paid_validated >= 100
ORDER BY free_validation_to_activation_pct - paid_validation_to_activation_pct;

-- Final timing check: how many validated companies activated only after the
-- fair 90-day window? This shows whether Free is merely slower or truly has a
-- larger unactivated population in the available data.
WITH base AS (
    SELECT
        initial_subscription_group,
        company_signup_at::DATE AS signup_date,
        validation_date,
        activation_date
    FROM companies
    WHERE company_signup_at >= DATE '2025-10-01'
      AND company_signup_at <  DATE '2026-01-31'
      AND validation_date BETWEEN company_signup_at::DATE
                              AND company_signup_at::DATE + INTERVAL 90 DAY
)
SELECT
    initial_subscription_group AS segment,
    COUNT(*) AS validated,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE activation_date > signup_date + INTERVAL 90 DAY
        ) / COUNT(*),
        1
    ) AS activated_after_90d_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE activation_date IS NULL)
        / COUNT(*),
        1
    ) AS still_no_activation_in_extract_pct
FROM base
GROUP BY 1
ORDER BY still_no_activation_in_extract_pct DESC;
