-- Shine case: requested KPI deep dive
-- This script runs after sql/shine_eda.sql and uses its typed source tables.
-- Core analysis ends at analysis_parameters.confirmed_end_month (April 2026).

-- Remove the obsolete closure-based churn table from earlier versions. Closure
-- is retained below only as a descriptive account/profile event.
DROP TABLE IF EXISTS eda_churn_monthly_by_segment;

-- Revenue is monthly, so state thresholds are expressed in complete inactive
-- months. Three months is approximately 90 days, not an exact day count.
CREATE OR REPLACE TABLE revenue_state_parameters AS
SELECT
    1 AS at_risk_after_inactive_months,
    3 AS churned_after_inactive_months,
    2 AS return_measurement_horizon_months;

-- ============================================================
-- 1. NEW-COMPANY TRENDS
-- ============================================================
-- "New company" means a new company profile/signup, not an activated account.
-- May is excluded because only 1 May is present in the signup source.

CREATE OR REPLACE TABLE eda_new_companies_by_month_segment AS
WITH aggregated AS (
    SELECT
        DATE_TRUNC('month', company_signup_at)::DATE AS signup_month,
        CASE WHEN GROUPING(persona) = 1 THEN 'ALL' ELSE persona END AS persona,
        CASE
            WHEN GROUPING(initial_subscription_group) = 1 THEN 'ALL'
            ELSE initial_subscription_group
        END AS initial_subscription_group,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1 THEN 'overall'
            WHEN GROUPING(persona) = 0
             AND GROUPING(initial_subscription_group) = 1 THEN 'persona'
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 0 THEN 'initial_plan'
            ELSE 'persona_x_initial_plan'
        END AS segment_level,
        COUNT(*) AS new_companies
    FROM companies
    WHERE company_signup_at::DATE
          < (SELECT provisional_month FROM analysis_parameters)
    GROUP BY GROUPING SETS (
        (DATE_TRUNC('month', company_signup_at)),
        (DATE_TRUNC('month', company_signup_at), persona),
        (DATE_TRUNC('month', company_signup_at), initial_subscription_group),
        (
            DATE_TRUNC('month', company_signup_at),
            persona,
            initial_subscription_group
        )
    )
)
SELECT *
FROM aggregated
ORDER BY signup_month, segment_level, persona, initial_subscription_group;

-- ============================================================
-- 2. THIRTY-DAY FUNNEL, DROPOUT, AND PRE-ACTIVATION CLOSURE
-- ============================================================
-- A fixed 30-day outcome window makes signup cohorts comparable and prevents
-- April signups from looking worse simply because they have less observation.
-- Eligible signups therefore end 30 days before the April observation date.
--
-- Definitions:
--   validation dropout = not validated within 30 days of signup
--   activation dropout = validated within 30 days but not activated within
--                        30 days of signup
--   total funnel dropout = not activated within 30 days of signup
--   pre-activation closure = closed within 30 days and never activated
--
-- Pre-activation closure is a data label, not proof of KYB rejection. It may
-- also contain abandonment or operational closure.

CREATE OR REPLACE TABLE eda_funnel_30d_by_signup_month_segment AS
WITH cutoff AS (
    SELECT
        (
            confirmed_end_month
            + INTERVAL '1 month'
            - INTERVAL '1 day'
        )::DATE AS observation_end_date
    FROM analysis_parameters
),
eligible AS (
    SELECT
        DATE_TRUNC('month', c.company_signup_at)::DATE AS signup_month,
        c.company_signup_at::DATE AS signup_date,
        c.persona,
        c.initial_subscription_group,
        c.validation_date,
        c.activation_date,
        c.closed_date,
        c.validation_date IS NOT NULL
            AND c.validation_date <= c.company_signup_at::DATE + 30
            AS validated_within_30d,
        c.activation_date IS NOT NULL
            AND c.activation_date <= c.company_signup_at::DATE + 30
            AS activated_within_30d,
        c.closed_date IS NOT NULL
            AND c.closed_date <= c.company_signup_at::DATE + 30
            AND c.activation_date IS NULL
            AS pre_activation_closed_within_30d
    FROM companies c
    CROSS JOIN cutoff x
    WHERE c.company_signup_at::DATE <= x.observation_end_date - 30
),
aggregated AS (
    SELECT
        signup_month,
        CASE WHEN GROUPING(persona) = 1 THEN 'ALL' ELSE persona END AS persona,
        CASE
            WHEN GROUPING(initial_subscription_group) = 1 THEN 'ALL'
            ELSE initial_subscription_group
        END AS initial_subscription_group,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1 THEN 'overall'
            WHEN GROUPING(persona) = 0
             AND GROUPING(initial_subscription_group) = 1 THEN 'persona'
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 0 THEN 'initial_plan'
            ELSE 'persona_x_initial_plan'
        END AS segment_level,
        COUNT(*) AS eligible_signups,
        COUNT(*) FILTER (WHERE validated_within_30d) AS validated_within_30d,
        COUNT(*) FILTER (WHERE activated_within_30d) AS activated_within_30d,
        COUNT(*) FILTER (WHERE pre_activation_closed_within_30d)
            AS pre_activation_closed_within_30d
    FROM eligible
    GROUP BY GROUPING SETS (
        (signup_month),
        (signup_month, persona),
        (signup_month, initial_subscription_group),
        (signup_month, persona, initial_subscription_group)
    )
)
SELECT
    *,
    ROUND(
        100.0 * (eligible_signups - validated_within_30d)
        / NULLIF(eligible_signups, 0),
        1
    ) AS signup_to_validation_dropout_pct,
    ROUND(
        100.0 * (validated_within_30d - activated_within_30d)
        / NULLIF(validated_within_30d, 0),
        1
    ) AS validation_to_activation_dropout_pct,
    ROUND(
        100.0 * (eligible_signups - activated_within_30d)
        / NULLIF(eligible_signups, 0),
        1
    ) AS total_signup_to_activation_dropout_pct,
    ROUND(
        100.0 * pre_activation_closed_within_30d
        / NULLIF(eligible_signups, 0),
        1
    ) AS pre_activation_closure_rate_pct
FROM aggregated
ORDER BY signup_month, segment_level, persona, initial_subscription_group;

-- ============================================================
-- 3. MONTHLY POST-ACTIVATION CLOSURES (NOT CHURN)
-- ============================================================
-- This table describes profile/account closures after activation. It is kept
-- for operational context, but must not be interpreted as subscription churn.

CREATE OR REPLACE TABLE eda_post_activation_closures_monthly_by_segment AS
WITH months AS (
    SELECT gs.month_start::DATE AS month_start
    FROM analysis_parameters p,
    LATERAL GENERATE_SERIES(
        DATE '2025-10-01',
        p.confirmed_end_month,
        INTERVAL '1 month'
    ) AS gs(month_start)
),
company_month AS (
    SELECT
        m.month_start,
        c.company_profile_id,
        c.persona,
        c.initial_subscription_group,
        c.activation_date,
        c.closed_date
    FROM months m
    CROSS JOIN companies c
    WHERE c.activation_date IS NOT NULL
      AND c.activation_date
          < m.month_start + INTERVAL '1 month'
),
aggregated AS (
    SELECT
        month_start,
        CASE WHEN GROUPING(persona) = 1 THEN 'ALL' ELSE persona END AS persona,
        CASE
            WHEN GROUPING(initial_subscription_group) = 1 THEN 'ALL'
            ELSE initial_subscription_group
        END AS initial_subscription_group,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1 THEN 'overall'
            WHEN GROUPING(persona) = 0
             AND GROUPING(initial_subscription_group) = 1 THEN 'persona'
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 0 THEN 'initial_plan'
            ELSE 'persona_x_initial_plan'
        END AS segment_level,
        COUNT(*) FILTER (
            WHERE activation_date < month_start
              AND (closed_date IS NULL OR closed_date >= month_start)
        ) AS active_at_start,
        COUNT(*) FILTER (
            WHERE activation_date < month_start
              AND closed_date >= month_start
              AND closed_date < month_start + INTERVAL '1 month'
        ) AS post_activation_closed_during_month,
        COUNT(*) FILTER (
            WHERE activation_date >= month_start
              AND activation_date < month_start + INTERVAL '1 month'
        ) AS activated_during_month,
        COUNT(*) FILTER (
            WHERE activation_date >= month_start
              AND activation_date < month_start + INTERVAL '1 month'
              AND closed_date >= activation_date
              AND closed_date < month_start + INTERVAL '1 month'
        ) AS activated_and_closed_same_month,
        COUNT(*) FILTER (
            WHERE activation_date < month_start + INTERVAL '1 month'
              AND (
                  closed_date IS NULL
                  OR closed_date >= month_start + INTERVAL '1 month'
              )
        ) AS active_at_end
    FROM company_month
    GROUP BY GROUPING SETS (
        (month_start),
        (month_start, persona),
        (month_start, initial_subscription_group),
        (month_start, persona, initial_subscription_group)
    )
)
SELECT
    *,
    ROUND(
        100.0 * post_activation_closed_during_month
        / NULLIF(active_at_start, 0),
        2
    ) AS monthly_post_activation_closure_rate_pct
FROM aggregated
ORDER BY month_start, segment_level, persona, initial_subscription_group;

-- ============================================================
-- 4. REVENUE-ACTIVITY TRANSITIONS
-- ============================================================
-- This is the preferred churn-like diagnostic:
--   retained: revenue row in both prior and current month
--   dropped: revenue row in prior month but not current month
--   new revenue company: first observed revenue row is current month
--   reactivated: current revenue row, no prior-month row, but earlier revenue
--
-- A one-month dropout is not declared churn because companies can reactivate
-- and the source may omit zero-revenue company-months.

CREATE OR REPLACE TABLE eda_revenue_activity_transitions_by_segment AS
WITH months AS (
    SELECT gs.month_start::DATE AS month_start
    FROM analysis_parameters p,
    LATERAL GENERATE_SERIES(
        DATE '2025-11-01',
        p.confirmed_end_month,
        INTERVAL '1 month'
    ) AS gs(month_start)
),
revenue_span AS (
    SELECT
        company_profile_id,
        MIN(revenue_month) AS first_revenue_month
    FROM revenue
    WHERE revenue_month <= (SELECT confirmed_end_month FROM analysis_parameters)
    GROUP BY company_profile_id
),
company_month AS (
    SELECT
        m.month_start,
        s.company_profile_id,
        c.persona,
        c.initial_subscription_group,
        s.first_revenue_month,
        p.subscription_revenue AS prior_subscription_revenue,
        p.interchange_revenue AS prior_interchange_revenue,
        p.banking_fees AS prior_banking_fees,
        p.deposit_interest_revenue AS prior_deposit_interest_revenue,
        p.total_revenue AS prior_total_revenue,
        current_month.company_profile_id IS NOT NULL AS has_current_revenue
    FROM months m
    CROSS JOIN revenue_span s
    JOIN companies c USING (company_profile_id)
    LEFT JOIN revenue_with_total p
        ON s.company_profile_id = p.company_profile_id
       AND p.revenue_month = m.month_start - INTERVAL '1 month'
    LEFT JOIN revenue_with_total current_month
        ON s.company_profile_id = current_month.company_profile_id
       AND current_month.revenue_month = m.month_start
),
aggregated AS (
    SELECT
        month_start,
        CASE WHEN GROUPING(persona) = 1 THEN 'ALL' ELSE persona END AS persona,
        CASE
            WHEN GROUPING(initial_subscription_group) = 1 THEN 'ALL'
            ELSE initial_subscription_group
        END AS initial_subscription_group,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1 THEN 'overall'
            WHEN GROUPING(persona) = 0
             AND GROUPING(initial_subscription_group) = 1 THEN 'persona'
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 0 THEN 'initial_plan'
            ELSE 'persona_x_initial_plan'
        END AS segment_level,
        COUNT(*) FILTER (WHERE prior_total_revenue IS NOT NULL)
            AS prior_revenue_companies,
        COUNT(*) FILTER (
            WHERE prior_total_revenue IS NOT NULL AND has_current_revenue
        ) AS retained_revenue_companies,
        COUNT(*) FILTER (
            WHERE prior_total_revenue IS NOT NULL AND NOT has_current_revenue
        ) AS revenue_company_dropouts,
        COUNT(*) FILTER (
            WHERE has_current_revenue AND first_revenue_month = month_start
        ) AS new_revenue_companies,
        COUNT(*) FILTER (
            WHERE has_current_revenue
              AND prior_total_revenue IS NULL
              AND first_revenue_month < month_start
        ) AS reactivated_revenue_companies,
        SUM(prior_subscription_revenue) AS prior_subscription_revenue,
        SUM(prior_interchange_revenue) AS prior_interchange_revenue,
        SUM(prior_banking_fees) AS prior_banking_fees,
        SUM(prior_deposit_interest_revenue) AS prior_deposit_interest_revenue,
        SUM(prior_total_revenue) AS prior_total_revenue,
        SUM(prior_subscription_revenue) FILTER (WHERE NOT has_current_revenue)
            AS dropped_prior_subscription_revenue,
        SUM(prior_interchange_revenue) FILTER (WHERE NOT has_current_revenue)
            AS dropped_prior_interchange_revenue,
        SUM(prior_banking_fees) FILTER (WHERE NOT has_current_revenue)
            AS dropped_prior_banking_fees,
        SUM(prior_deposit_interest_revenue) FILTER (WHERE NOT has_current_revenue)
            AS dropped_prior_deposit_interest_revenue,
        SUM(prior_total_revenue) FILTER (WHERE NOT has_current_revenue)
            AS dropped_prior_total_revenue
    FROM company_month
    GROUP BY GROUPING SETS (
        (month_start),
        (month_start, persona),
        (month_start, initial_subscription_group),
        (month_start, persona, initial_subscription_group)
    )
)
SELECT
    *,
    ROUND(
        100.0 * revenue_company_dropouts
        / NULLIF(prior_revenue_companies, 0),
        2
    ) AS one_month_revenue_company_dropout_pct,
    ROUND(
        100.0 * dropped_prior_total_revenue
        / NULLIF(prior_total_revenue, 0),
        2
    ) AS one_month_gross_revenue_dropout_pct
FROM aggregated
ORDER BY month_start, segment_level, persona, initial_subscription_group;

-- Revenue amount associated with companies that disappear in the following
-- month, split by component. Values are their prior-month revenue, not a causal
-- estimate of permanently lost revenue.
CREATE OR REPLACE TABLE eda_revenue_dropout_by_segment_type AS
WITH long_form AS (
    SELECT month_start, persona, initial_subscription_group, segment_level,
           'Subscription' AS revenue_type,
           prior_subscription_revenue AS prior_revenue,
           dropped_prior_subscription_revenue AS dropped_prior_revenue
    FROM eda_revenue_activity_transitions_by_segment
    UNION ALL
    SELECT month_start, persona, initial_subscription_group, segment_level,
           'Interchange', prior_interchange_revenue,
           dropped_prior_interchange_revenue
    FROM eda_revenue_activity_transitions_by_segment
    UNION ALL
    SELECT month_start, persona, initial_subscription_group, segment_level,
           'Banking fees', prior_banking_fees, dropped_prior_banking_fees
    FROM eda_revenue_activity_transitions_by_segment
    UNION ALL
    SELECT month_start, persona, initial_subscription_group, segment_level,
           'Deposit interest', prior_deposit_interest_revenue,
           dropped_prior_deposit_interest_revenue
    FROM eda_revenue_activity_transitions_by_segment
    UNION ALL
    SELECT month_start, persona, initial_subscription_group, segment_level,
           'Total revenue', prior_total_revenue, dropped_prior_total_revenue
    FROM eda_revenue_activity_transitions_by_segment
)
SELECT
    *,
    ROUND(
        100.0 * dropped_prior_revenue / NULLIF(prior_revenue, 0),
        2
    ) AS one_month_gross_revenue_dropout_pct
FROM long_form
ORDER BY
    month_start,
    segment_level,
    persona,
    initial_subscription_group,
    revenue_type;

-- ============================================================
-- 5. SUSTAINED REVENUE INACTIVITY AS OF APRIL
-- ============================================================
-- The denominator for each threshold includes only companies observed early
-- enough to have the full inactivity window available.

CREATE OR REPLACE TABLE eda_sustained_revenue_inactivity_by_segment AS
WITH span AS (
    SELECT
        r.company_profile_id,
        c.persona,
        c.initial_subscription_group,
        MIN(r.revenue_month) AS first_revenue_month,
        MAX(r.revenue_month) AS last_revenue_month
    FROM revenue r
    JOIN companies c USING (company_profile_id)
    WHERE r.revenue_month <= (SELECT confirmed_end_month FROM analysis_parameters)
    GROUP BY r.company_profile_id, c.persona, c.initial_subscription_group
),
aggregated AS (
    SELECT
        CASE WHEN GROUPING(persona) = 1 THEN 'ALL' ELSE persona END AS persona,
        CASE
            WHEN GROUPING(initial_subscription_group) = 1 THEN 'ALL'
            ELSE initial_subscription_group
        END AS initial_subscription_group,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1 THEN 'overall'
            WHEN GROUPING(persona) = 0
             AND GROUPING(initial_subscription_group) = 1 THEN 'persona'
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 0 THEN 'initial_plan'
            ELSE 'persona_x_initial_plan'
        END AS segment_level,
        COUNT(*) FILTER (
            WHERE first_revenue_month
                  <= (SELECT confirmed_end_month FROM analysis_parameters) - INTERVAL '1 month'
        ) AS eligible_for_1_month_inactivity,
        COUNT(*) FILTER (
            WHERE last_revenue_month
                  <= (SELECT confirmed_end_month FROM analysis_parameters) - INTERVAL '1 month'
        ) AS inactive_for_at_least_1_month,
        COUNT(*) FILTER (
            WHERE first_revenue_month
                  <= (SELECT confirmed_end_month FROM analysis_parameters) - INTERVAL '2 months'
        ) AS eligible_for_2_month_inactivity,
        COUNT(*) FILTER (
            WHERE last_revenue_month
                  <= (SELECT confirmed_end_month FROM analysis_parameters) - INTERVAL '2 months'
        ) AS inactive_for_at_least_2_months,
        COUNT(*) FILTER (
            WHERE first_revenue_month
                  <= (SELECT confirmed_end_month FROM analysis_parameters) - INTERVAL '3 months'
        ) AS eligible_for_3_month_inactivity,
        COUNT(*) FILTER (
            WHERE last_revenue_month
                  <= (SELECT confirmed_end_month FROM analysis_parameters) - INTERVAL '3 months'
        ) AS inactive_for_at_least_3_months
    FROM span
    GROUP BY GROUPING SETS (
        (),
        (persona),
        (initial_subscription_group),
        (persona, initial_subscription_group)
    )
)
SELECT
    *,
    ROUND(
        100.0 * inactive_for_at_least_1_month
        / NULLIF(eligible_for_1_month_inactivity, 0),
        2
    ) AS sustained_1_month_inactivity_rate_pct,
    ROUND(
        100.0 * inactive_for_at_least_2_months
        / NULLIF(eligible_for_2_month_inactivity, 0),
        2
    ) AS sustained_2_month_inactivity_rate_pct,
    ROUND(
        100.0 * inactive_for_at_least_3_months
        / NULLIF(eligible_for_3_month_inactivity, 0),
        2
    ) AS sustained_3_month_inactivity_rate_pct
FROM aggregated
ORDER BY segment_level, persona, initial_subscription_group;

-- Monthly incidence of confirmed two-month inactivity. For reporting month t,
-- the denominator is companies with revenue in t-2 and the numerator is those
-- absent in both t-1 and t. This is the closest churn-like flow metric in the
-- supplied data, though later reactivation remains possible.
CREATE OR REPLACE TABLE eda_two_month_revenue_inactivity_by_segment AS
WITH months AS (
    SELECT gs.reporting_month::DATE AS reporting_month
    FROM analysis_parameters p,
    LATERAL GENERATE_SERIES(
        DATE '2025-12-01',
        p.confirmed_end_month,
        INTERVAL '1 month'
    ) AS gs(reporting_month)
),
company_window AS (
    SELECT
        m.reporting_month,
        base.company_profile_id,
        c.persona,
        c.initial_subscription_group,
        base.total_revenue AS base_month_revenue,
        middle_month.company_profile_id IS NOT NULL AS present_in_middle_month,
        reporting.company_profile_id IS NOT NULL AS present_in_reporting_month
    FROM months m
    JOIN revenue_with_total base
        ON base.revenue_month = m.reporting_month - INTERVAL '2 months'
    JOIN companies c USING (company_profile_id)
    LEFT JOIN revenue middle_month
        ON base.company_profile_id = middle_month.company_profile_id
       AND middle_month.revenue_month = m.reporting_month - INTERVAL '1 month'
    LEFT JOIN revenue reporting
        ON base.company_profile_id = reporting.company_profile_id
       AND reporting.revenue_month = m.reporting_month
),
aggregated AS (
    SELECT
        reporting_month,
        CASE WHEN GROUPING(persona) = 1 THEN 'ALL' ELSE persona END AS persona,
        CASE
            WHEN GROUPING(initial_subscription_group) = 1 THEN 'ALL'
            ELSE initial_subscription_group
        END AS initial_subscription_group,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1 THEN 'overall'
            WHEN GROUPING(persona) = 0
             AND GROUPING(initial_subscription_group) = 1 THEN 'persona'
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 0 THEN 'initial_plan'
            ELSE 'persona_x_initial_plan'
        END AS segment_level,
        COUNT(*) AS revenue_companies_two_months_prior,
        COUNT(*) FILTER (
            WHERE NOT present_in_middle_month
              AND NOT present_in_reporting_month
        ) AS confirmed_two_month_inactive_companies,
        SUM(base_month_revenue) AS base_month_revenue,
        SUM(base_month_revenue) FILTER (
            WHERE NOT present_in_middle_month
              AND NOT present_in_reporting_month
        ) AS revenue_from_confirmed_inactive_companies
    FROM company_window
    GROUP BY GROUPING SETS (
        (reporting_month),
        (reporting_month, persona),
        (reporting_month, initial_subscription_group),
        (reporting_month, persona, initial_subscription_group)
    )
)
SELECT
    *,
    ROUND(
        100.0 * confirmed_two_month_inactive_companies
        / NULLIF(revenue_companies_two_months_prior, 0),
        2
    ) AS confirmed_two_month_inactivity_rate_pct,
    ROUND(
        100.0 * revenue_from_confirmed_inactive_companies
        / NULLIF(base_month_revenue, 0),
        2
    ) AS confirmed_two_month_revenue_rate_pct
FROM aggregated
ORDER BY reporting_month, segment_level, persona, initial_subscription_group;

-- ============================================================
-- 6. RETURN PROBABILITY AFTER INACTIVITY
-- ============================================================
-- One row in the underlying population is an inactivity spell, not necessarily
-- a unique company. A company can have multiple spells if it returns and later
-- becomes inactive again.
--
-- "Observed return lower bound" counts completed returns by April and treats
-- unresolved end-of-window spells as not returned. The fixed one-/two-month
-- measures reduce right-censoring by including only spells with the full future
-- observation horizon available.

CREATE OR REPLACE TABLE eda_revenue_return_probability_curve AS
WITH ordered AS (
    SELECT
        r.company_profile_id,
        c.persona,
        c.initial_subscription_group,
        r.revenue_month AS last_active_month,
        LEAD(r.revenue_month) OVER (
            PARTITION BY r.company_profile_id
            ORDER BY r.revenue_month
        ) AS next_active_month
    FROM revenue r
    JOIN companies c USING (company_profile_id)
    WHERE r.revenue_month <= (SELECT confirmed_end_month FROM analysis_parameters)
),
spell_candidates AS (
    SELECT
        *,
        CASE
            WHEN next_active_month IS NULL THEN DATE_DIFF(
                'month',
                last_active_month,
                (SELECT confirmed_end_month FROM analysis_parameters)
            )
            ELSE DATE_DIFF('month', last_active_month, next_active_month) - 1
        END AS observed_inactive_months,
        next_active_month IS NOT NULL AS returned_in_observed_window
    FROM ordered
),
spells AS (
    SELECT *
    FROM spell_candidates
    WHERE observed_inactive_months >= 1
),
thresholds AS (
    SELECT
        s.*,
        k.inactive_months,
        (
            s.last_active_month
            + k.inactive_months * INTERVAL '1 month'
        )::DATE AS threshold_month
    FROM spells s,
    LATERAL GENERATE_SERIES(
        1,
        s.observed_inactive_months
    ) AS k(inactive_months)
),
aggregated AS (
    SELECT
        inactive_months,
        CASE WHEN GROUPING(persona) = 1 THEN 'ALL' ELSE persona END AS persona,
        CASE
            WHEN GROUPING(initial_subscription_group) = 1 THEN 'ALL'
            ELSE initial_subscription_group
        END AS initial_subscription_group,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1 THEN 'overall'
            WHEN GROUPING(persona) = 0
             AND GROUPING(initial_subscription_group) = 1 THEN 'persona'
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 0 THEN 'initial_plan'
            ELSE 'persona_x_initial_plan'
        END AS segment_level,
        COUNT(*) AS spells_reaching_inactivity_threshold,
        COUNT(*) FILTER (WHERE returned_in_observed_window)
            AS eventually_returned_in_observed_window,
        COUNT(*) FILTER (WHERE NOT returned_in_observed_window)
            AS unresolved_at_april_cutoff,
        COUNT(*) FILTER (
            WHERE threshold_month + INTERVAL '1 month'
                  <= (SELECT confirmed_end_month FROM analysis_parameters)
        ) AS spells_with_1_month_followup,
        COUNT(*) FILTER (
            WHERE threshold_month + INTERVAL '1 month'
                  <= (SELECT confirmed_end_month FROM analysis_parameters)
              AND next_active_month
                  <= threshold_month + INTERVAL '1 month'
        ) AS returned_within_next_1_month,
        COUNT(*) FILTER (
            WHERE threshold_month + INTERVAL '2 months'
                  <= (SELECT confirmed_end_month FROM analysis_parameters)
        ) AS spells_with_2_month_followup,
        COUNT(*) FILTER (
            WHERE threshold_month + INTERVAL '2 months'
                  <= (SELECT confirmed_end_month FROM analysis_parameters)
              AND next_active_month
                  <= threshold_month + INTERVAL '2 months'
        ) AS returned_within_next_2_months
    FROM thresholds
    GROUP BY GROUPING SETS (
        (inactive_months),
        (inactive_months, persona),
        (inactive_months, initial_subscription_group),
        (inactive_months, persona, initial_subscription_group)
    )
)
SELECT
    *,
    ROUND(
        100.0 * eventually_returned_in_observed_window
        / NULLIF(spells_reaching_inactivity_threshold, 0),
        1
    ) AS observed_return_lower_bound_pct,
    ROUND(
        100.0 * returned_within_next_1_month
        / NULLIF(spells_with_1_month_followup, 0),
        1
    ) AS return_within_next_1_month_pct,
    ROUND(
        100.0 * returned_within_next_2_months
        / NULLIF(spells_with_2_month_followup, 0),
        1
    ) AS return_within_next_2_months_pct
FROM aggregated
ORDER BY inactive_months, segment_level, persona, initial_subscription_group;

-- ============================================================
-- 7. ACTIVE / AT-RISK / CHURNED-PROXY STATES AS OF APRIL
-- ============================================================

CREATE OR REPLACE TABLE eda_company_revenue_lifecycle_state AS
WITH span AS (
    SELECT
        company_profile_id,
        MIN(revenue_month) AS first_revenue_month,
        MAX(revenue_month) AS last_revenue_month
    FROM revenue
    WHERE revenue_month <= (SELECT confirmed_end_month FROM analysis_parameters)
    GROUP BY company_profile_id
)
SELECT
    s.company_profile_id,
    c.persona,
    c.initial_subscription_group,
    s.first_revenue_month,
    s.last_revenue_month,
    DATE_DIFF(
        'month',
        s.last_revenue_month,
        (SELECT confirmed_end_month FROM analysis_parameters)
    ) AS inactive_months_at_cutoff,
    CASE
        WHEN s.last_revenue_month
             = (SELECT confirmed_end_month FROM analysis_parameters)
            THEN 'Active'
        WHEN DATE_DIFF(
            'month',
            s.last_revenue_month,
            (SELECT confirmed_end_month FROM analysis_parameters)
        ) < (SELECT churned_after_inactive_months FROM revenue_state_parameters)
            THEN 'At-risk'
        ELSE 'Churned proxy'
    END AS revenue_lifecycle_state,
    last_revenue.subscription_revenue AS last_subscription_revenue,
    last_revenue.interchange_revenue AS last_interchange_revenue,
    last_revenue.banking_fees AS last_banking_fees,
    last_revenue.deposit_interest_revenue AS last_deposit_interest_revenue,
    last_revenue.total_revenue AS last_total_revenue
FROM span s
JOIN companies c USING (company_profile_id)
JOIN revenue_with_total last_revenue
    ON s.company_profile_id = last_revenue.company_profile_id
   AND s.last_revenue_month = last_revenue.revenue_month;

CREATE OR REPLACE TABLE eda_revenue_lifecycle_state_by_segment AS
WITH aggregated AS (
    SELECT
        revenue_lifecycle_state,
        CASE WHEN GROUPING(persona) = 1 THEN 'ALL' ELSE persona END AS persona,
        CASE
            WHEN GROUPING(initial_subscription_group) = 1 THEN 'ALL'
            ELSE initial_subscription_group
        END AS initial_subscription_group,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1 THEN 'overall'
            WHEN GROUPING(persona) = 0
             AND GROUPING(initial_subscription_group) = 1 THEN 'persona'
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 0 THEN 'initial_plan'
            ELSE 'persona_x_initial_plan'
        END AS segment_level,
        COUNT(*) AS companies,
        SUM(last_subscription_revenue) AS last_subscription_revenue,
        SUM(last_interchange_revenue) AS last_interchange_revenue,
        SUM(last_banking_fees) AS last_banking_fees,
        SUM(last_deposit_interest_revenue) AS last_deposit_interest_revenue,
        SUM(last_total_revenue) AS last_total_revenue
    FROM eda_company_revenue_lifecycle_state
    GROUP BY GROUPING SETS (
        (revenue_lifecycle_state),
        (revenue_lifecycle_state, persona),
        (revenue_lifecycle_state, initial_subscription_group),
        (
            revenue_lifecycle_state,
            persona,
            initial_subscription_group
        )
    )
)
SELECT
    *,
    ROUND(
        100.0 * companies
        / SUM(companies) OVER (
            PARTITION BY segment_level, persona, initial_subscription_group
        ),
        2
    ) AS segment_company_share_pct
FROM aggregated
ORDER BY segment_level, persona, initial_subscription_group,
    CASE revenue_lifecycle_state
        WHEN 'Active' THEN 1
        WHEN 'At-risk' THEN 2
        ELSE 3
    END;

CREATE OR REPLACE TABLE eda_revenue_lifecycle_state_by_segment_type AS
WITH long_form AS (
    SELECT revenue_lifecycle_state, persona, initial_subscription_group,
           segment_level, companies, segment_company_share_pct,
           'Subscription' AS revenue_type,
           last_subscription_revenue AS last_observed_revenue
    FROM eda_revenue_lifecycle_state_by_segment
    UNION ALL
    SELECT revenue_lifecycle_state, persona, initial_subscription_group,
           segment_level, companies, segment_company_share_pct,
           'Interchange', last_interchange_revenue
    FROM eda_revenue_lifecycle_state_by_segment
    UNION ALL
    SELECT revenue_lifecycle_state, persona, initial_subscription_group,
           segment_level, companies, segment_company_share_pct,
           'Banking fees', last_banking_fees
    FROM eda_revenue_lifecycle_state_by_segment
    UNION ALL
    SELECT revenue_lifecycle_state, persona, initial_subscription_group,
           segment_level, companies, segment_company_share_pct,
           'Deposit interest', last_deposit_interest_revenue
    FROM eda_revenue_lifecycle_state_by_segment
    UNION ALL
    SELECT revenue_lifecycle_state, persona, initial_subscription_group,
           segment_level, companies, segment_company_share_pct,
           'Total revenue', last_total_revenue
    FROM eda_revenue_lifecycle_state_by_segment
)
SELECT *
FROM long_form
ORDER BY
    segment_level,
    persona,
    initial_subscription_group,
    revenue_lifecycle_state,
    revenue_type;

-- ============================================================
-- 8. REVENUE TRENDS BY SEGMENT AND REVENUE TYPE
-- ============================================================

CREATE OR REPLACE TABLE eda_revenue_trends_by_segment_type AS
WITH base AS (
    SELECT
        r.revenue_month,
        c.persona,
        c.initial_subscription_group,
        COUNT(DISTINCT r.company_profile_id) AS revenue_companies,
        SUM(r.subscription_revenue) AS subscription,
        SUM(r.interchange_revenue) AS interchange,
        SUM(r.banking_fees) AS banking_fees,
        SUM(r.deposit_interest_revenue) AS deposit_interest,
        SUM(r.total_revenue) AS total_revenue
    FROM revenue_with_total r
    JOIN companies c USING (company_profile_id)
    WHERE r.revenue_month
          <= (SELECT confirmed_end_month FROM analysis_parameters)
    GROUP BY r.revenue_month, c.persona, c.initial_subscription_group
),
long_form AS (
    SELECT revenue_month, persona, initial_subscription_group,
           revenue_companies, 'Subscription' AS revenue_type,
           subscription AS revenue
    FROM base
    UNION ALL
    SELECT revenue_month, persona, initial_subscription_group,
           revenue_companies, 'Interchange', interchange
    FROM base
    UNION ALL
    SELECT revenue_month, persona, initial_subscription_group,
           revenue_companies, 'Banking fees', banking_fees
    FROM base
    UNION ALL
    SELECT revenue_month, persona, initial_subscription_group,
           revenue_companies, 'Deposit interest', deposit_interest
    FROM base
    UNION ALL
    SELECT revenue_month, persona, initial_subscription_group,
           revenue_companies, 'Total revenue', total_revenue
    FROM base
)
SELECT
    revenue_month,
    persona,
    initial_subscription_group,
    revenue_type,
    revenue_companies,
    revenue,
    revenue / NULLIF(revenue_companies, 0)
        AS revenue_per_revenue_company
FROM long_form
ORDER BY
    revenue_month,
    persona,
    initial_subscription_group,
    revenue_type;

-- ============================================================
-- 9. OBSERVED LTV PROXY BY COHORT AGE, SEGMENT, AND REVENUE TYPE
-- ============================================================
-- This is not forecast LTV. It is cumulative observed revenue divided by the
-- original activated cohort size. A complete company-month spine treats absent
-- revenue rows as zero for this explicit sensitivity definition.

CREATE OR REPLACE TABLE eda_ltv_proxy_by_cohort_age_segment_type AS
WITH eligible_companies AS (
    SELECT
        c.company_profile_id,
        c.persona,
        c.initial_subscription_group,
        DATE_TRUNC('month', c.activation_date)::DATE AS activation_month
    FROM companies c
    WHERE c.activation_date IS NOT NULL
      AND DATE_TRUNC('month', c.activation_date)::DATE
          <= (SELECT confirmed_end_month FROM analysis_parameters)
),
company_spine AS (
    SELECT
        c.company_profile_id,
        c.persona,
        c.initial_subscription_group,
        c.activation_month,
        gs.revenue_month::DATE AS revenue_month,
        DATE_DIFF('month', c.activation_month, gs.revenue_month::DATE)
            AS months_since_activation
    FROM eligible_companies c,
    LATERAL GENERATE_SERIES(
        c.activation_month,
        (SELECT confirmed_end_month FROM analysis_parameters),
        INTERVAL '1 month'
    ) AS gs(revenue_month)
),
company_month AS (
    SELECT
        s.*,
        COALESCE(r.subscription_revenue, 0) AS subscription,
        COALESCE(r.interchange_revenue, 0) AS interchange,
        COALESCE(r.banking_fees, 0) AS banking_fees,
        COALESCE(r.deposit_interest_revenue, 0) AS deposit_interest,
        COALESCE(r.total_revenue, 0) AS total_revenue
    FROM company_spine s
    LEFT JOIN revenue_with_total r
        ON s.company_profile_id = r.company_profile_id
       AND s.revenue_month = r.revenue_month
),
aggregated AS (
    SELECT
        activation_month,
        months_since_activation,
        CASE WHEN GROUPING(persona) = 1 THEN 'ALL' ELSE persona END AS persona,
        CASE
            WHEN GROUPING(initial_subscription_group) = 1 THEN 'ALL'
            ELSE initial_subscription_group
        END AS initial_subscription_group,
        CASE
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 1 THEN 'overall'
            WHEN GROUPING(persona) = 0
             AND GROUPING(initial_subscription_group) = 1 THEN 'persona'
            WHEN GROUPING(persona) = 1
             AND GROUPING(initial_subscription_group) = 0 THEN 'initial_plan'
            ELSE 'persona_x_initial_plan'
        END AS segment_level,
        COUNT(DISTINCT company_profile_id) AS activated_cohort_size,
        SUM(subscription) AS subscription,
        SUM(interchange) AS interchange,
        SUM(banking_fees) AS banking_fees,
        SUM(deposit_interest) AS deposit_interest,
        SUM(total_revenue) AS total_revenue
    FROM company_month
    GROUP BY GROUPING SETS (
        (activation_month, months_since_activation),
        (activation_month, months_since_activation, persona),
        (
            activation_month,
            months_since_activation,
            initial_subscription_group
        ),
        (
            activation_month,
            months_since_activation,
            persona,
            initial_subscription_group
        )
    )
),
long_form AS (
    SELECT *, 'Subscription' AS revenue_type, subscription AS monthly_revenue
    FROM aggregated
    UNION ALL
    SELECT *, 'Interchange', interchange FROM aggregated
    UNION ALL
    SELECT *, 'Banking fees', banking_fees FROM aggregated
    UNION ALL
    SELECT *, 'Deposit interest', deposit_interest FROM aggregated
    UNION ALL
    SELECT *, 'Total revenue', total_revenue FROM aggregated
),
with_cumulative AS (
    SELECT
        activation_month,
        months_since_activation,
        persona,
        initial_subscription_group,
        segment_level,
        revenue_type,
        activated_cohort_size,
        monthly_revenue,
        SUM(monthly_revenue) OVER (
            PARTITION BY
                activation_month,
                persona,
                initial_subscription_group,
                segment_level,
                revenue_type
            ORDER BY months_since_activation
        ) AS cumulative_revenue
    FROM long_form
)
SELECT
    activation_month,
    months_since_activation,
    persona,
    initial_subscription_group,
    segment_level,
    revenue_type,
    activated_cohort_size,
    monthly_revenue,
    cumulative_revenue,
    cumulative_revenue / NULLIF(activated_cohort_size, 0)
        AS observed_ltv_per_activated_company
FROM with_cumulative
ORDER BY
    activation_month,
    months_since_activation,
    segment_level,
    persona,
    initial_subscription_group,
    revenue_type;

-- ============================================================
-- 10. COMPACT SEGMENT SCORECARD
-- ============================================================
-- This is the easiest output to scan when choosing a persona or initial-plan
-- story. Funnel rates pool counts before calculating percentages.

CREATE OR REPLACE TABLE eda_segment_scorecard AS
WITH funnel AS (
    SELECT
        segment_level,
        persona,
        initial_subscription_group,
        SUM(eligible_signups) AS eligible_signups_30d,
        ROUND(
            100.0 * (SUM(eligible_signups) - SUM(activated_within_30d))
            / NULLIF(SUM(eligible_signups), 0),
            1
        ) AS total_funnel_dropout_30d_pct,
        ROUND(
            100.0 * SUM(pre_activation_closed_within_30d)
            / NULLIF(SUM(eligible_signups), 0),
            1
        ) AS pre_activation_closure_30d_pct
    FROM eda_funnel_30d_by_signup_month_segment
    WHERE segment_level IN ('persona', 'initial_plan')
    GROUP BY segment_level, persona, initial_subscription_group
),
new_companies AS (
    SELECT
        segment_level,
        persona,
        initial_subscription_group,
        new_companies AS april_new_companies
    FROM eda_new_companies_by_month_segment
    WHERE segment_level IN ('persona', 'initial_plan')
      AND signup_month = (SELECT confirmed_end_month FROM analysis_parameters)
),
revenue_transition AS (
    SELECT
        segment_level,
        persona,
        initial_subscription_group,
        prior_revenue_companies AS march_revenue_companies,
        retained_revenue_companies AS april_retained_revenue_companies,
        revenue_company_dropouts AS april_revenue_company_dropouts,
        reactivated_revenue_companies AS april_reactivated_revenue_companies,
        one_month_revenue_company_dropout_pct
            AS april_one_month_revenue_dropout_pct,
        one_month_gross_revenue_dropout_pct
            AS april_one_month_gross_revenue_dropout_pct
    FROM eda_revenue_activity_transitions_by_segment
    WHERE segment_level IN ('persona', 'initial_plan')
      AND month_start = (SELECT confirmed_end_month FROM analysis_parameters)
),
sustained_inactivity AS (
    SELECT
        segment_level,
        persona,
        initial_subscription_group,
        eligible_for_2_month_inactivity,
        inactive_for_at_least_2_months,
        sustained_2_month_inactivity_rate_pct
    FROM eda_sustained_revenue_inactivity_by_segment
    WHERE segment_level IN ('persona', 'initial_plan')
),
two_month_incidence AS (
    SELECT
        segment_level,
        persona,
        initial_subscription_group,
        revenue_companies_two_months_prior,
        confirmed_two_month_inactive_companies,
        confirmed_two_month_inactivity_rate_pct,
        confirmed_two_month_revenue_rate_pct
    FROM eda_two_month_revenue_inactivity_by_segment
    WHERE segment_level IN ('persona', 'initial_plan')
      AND reporting_month = (SELECT confirmed_end_month FROM analysis_parameters)
),
lifecycle_state AS (
    SELECT
        segment_level,
        persona,
        initial_subscription_group,
        SUM(companies) FILTER (WHERE revenue_lifecycle_state = 'Active')
            AS active_revenue_companies,
        SUM(companies) FILTER (WHERE revenue_lifecycle_state = 'At-risk')
            AS at_risk_revenue_companies,
        SUM(companies) FILTER (WHERE revenue_lifecycle_state = 'Churned proxy')
            AS churned_proxy_companies,
        MAX(segment_company_share_pct) FILTER (
            WHERE revenue_lifecycle_state = 'Active'
        ) AS active_revenue_company_share_pct,
        MAX(segment_company_share_pct) FILTER (
            WHERE revenue_lifecycle_state = 'At-risk'
        ) AS at_risk_revenue_company_share_pct,
        MAX(segment_company_share_pct) FILTER (
            WHERE revenue_lifecycle_state = 'Churned proxy'
        ) AS churned_proxy_company_share_pct
    FROM eda_revenue_lifecycle_state_by_segment
    WHERE segment_level IN ('persona', 'initial_plan')
    GROUP BY segment_level, persona, initial_subscription_group
),
april_revenue AS (
    SELECT
        'persona' AS segment_level,
        persona,
        'ALL' AS initial_subscription_group,
        revenue_companies AS april_revenue_companies,
        total_revenue AS april_total_revenue,
        average_revenue_per_company AS april_revenue_per_company
    FROM eda_april_revenue_by_persona
    UNION ALL
    SELECT
        'initial_plan',
        'ALL',
        initial_subscription_group,
        revenue_companies,
        total_revenue,
        average_revenue_per_company
    FROM eda_april_revenue_by_initial_plan
),
ltv AS (
    SELECT
        segment_level,
        persona,
        initial_subscription_group,
        SUM(activated_cohort_size) AS age_3_companies,
        ROUND(
            SUM(cumulative_revenue) / NULLIF(SUM(activated_cohort_size), 0),
            2
        ) AS observed_ltv_proxy_at_age_3
    FROM eda_ltv_proxy_by_cohort_age_segment_type
    WHERE segment_level IN ('persona', 'initial_plan')
      AND revenue_type = 'Total revenue'
      AND months_since_activation = 3
    GROUP BY segment_level, persona, initial_subscription_group
)
SELECT
    f.segment_level,
    f.persona,
    f.initial_subscription_group,
    f.eligible_signups_30d,
    f.total_funnel_dropout_30d_pct,
    f.pre_activation_closure_30d_pct,
    n.april_new_companies,
    t.march_revenue_companies,
    t.april_retained_revenue_companies,
    t.april_revenue_company_dropouts,
    t.april_reactivated_revenue_companies,
    t.april_one_month_revenue_dropout_pct,
    t.april_one_month_gross_revenue_dropout_pct,
    s.eligible_for_2_month_inactivity,
    s.inactive_for_at_least_2_months,
    s.sustained_2_month_inactivity_rate_pct,
    i.revenue_companies_two_months_prior,
    i.confirmed_two_month_inactive_companies,
    i.confirmed_two_month_inactivity_rate_pct,
    i.confirmed_two_month_revenue_rate_pct,
    ls.active_revenue_companies,
    ls.at_risk_revenue_companies,
    ls.churned_proxy_companies,
    ls.active_revenue_company_share_pct,
    ls.at_risk_revenue_company_share_pct,
    ls.churned_proxy_company_share_pct,
    r.april_revenue_companies,
    r.april_total_revenue,
    r.april_revenue_per_company,
    l.age_3_companies,
    l.observed_ltv_proxy_at_age_3
FROM funnel f
LEFT JOIN new_companies n USING (
    segment_level,
    persona,
    initial_subscription_group
)
LEFT JOIN revenue_transition t USING (
    segment_level,
    persona,
    initial_subscription_group
)
LEFT JOIN sustained_inactivity s USING (
    segment_level,
    persona,
    initial_subscription_group
)
LEFT JOIN two_month_incidence i USING (
    segment_level,
    persona,
    initial_subscription_group
)
LEFT JOIN lifecycle_state ls USING (
    segment_level,
    persona,
    initial_subscription_group
)
LEFT JOIN april_revenue r USING (
    segment_level,
    persona,
    initial_subscription_group
)
LEFT JOIN ltv l USING (
    segment_level,
    persona,
    initial_subscription_group
)
ORDER BY segment_level, april_total_revenue DESC;
