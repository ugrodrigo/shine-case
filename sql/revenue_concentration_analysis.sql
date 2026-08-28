-- Shine case: cumulative revenue concentration through confirmed April 2026
-- Runs after sql/shine_eda.sql.
--
-- "Top 10%" means the highest cumulative total-revenue companies among all
-- companies with at least one revenue row through April. ROW_NUMBER provides an
-- exact decile; company_profile_id is the deterministic tie-breaker.

CREATE OR REPLACE TABLE eda_company_cumulative_revenue_rank AS
WITH company_revenue AS (
    SELECT
        r.company_profile_id,
        c.persona,
        c.initial_subscription_group,
        SUM(r.subscription_revenue) AS subscription_revenue,
        SUM(r.interchange_revenue) AS interchange_revenue,
        SUM(r.banking_fees) AS banking_fees,
        SUM(r.deposit_interest_revenue) AS deposit_interest_revenue,
        SUM(r.total_revenue) AS cumulative_total_revenue
    FROM revenue_with_total r
    LEFT JOIN companies c USING (company_profile_id)
    WHERE r.revenue_month
          <= (SELECT confirmed_end_month FROM analysis_parameters)
    GROUP BY
        r.company_profile_id,
        c.persona,
        c.initial_subscription_group
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY cumulative_total_revenue DESC, company_profile_id
        ) AS revenue_rank,
        COUNT(*) OVER () AS revenue_company_population
    FROM company_revenue
)
SELECT
    *,
    CEIL(0.10 * revenue_company_population)::BIGINT AS top_decile_company_count,
    revenue_rank <= CEIL(0.10 * revenue_company_population) AS is_top_10pct,
    CEIL(0.20 * revenue_company_population)::BIGINT AS top_20pct_company_count,
    revenue_rank <= CEIL(0.20 * revenue_company_population) AS is_top_20pct
FROM ranked
ORDER BY revenue_rank;

CREATE OR REPLACE TABLE eda_top10_revenue_concentration_summary AS
WITH population AS (
    SELECT
        COUNT(*) FILTER (
            WHERE company_signup_at::DATE
                  < (SELECT provisional_month FROM analysis_parameters)
        ) AS confirmed_company_profiles,
        COUNT(*) FILTER (
            WHERE activation_date IS NOT NULL
              AND DATE_TRUNC('month', activation_date)::DATE
                  <= (SELECT confirmed_end_month FROM analysis_parameters)
        ) AS activated_companies_through_cutoff
    FROM companies
),
revenue AS (
    SELECT
        COUNT(*) AS revenue_companies,
        COUNT(*) FILTER (WHERE is_top_10pct) AS top_10pct_companies,
        SUM(cumulative_total_revenue) AS total_revenue,
        SUM(cumulative_total_revenue) FILTER (WHERE is_top_10pct)
            AS top_10pct_revenue,
        MIN(cumulative_total_revenue) FILTER (WHERE is_top_10pct)
            AS top_10pct_entry_revenue,
        AVG(cumulative_total_revenue) FILTER (WHERE is_top_10pct)
            AS top_10pct_average_revenue,
        MEDIAN(cumulative_total_revenue) FILTER (WHERE is_top_10pct)
            AS top_10pct_median_revenue,
        AVG(cumulative_total_revenue) FILTER (WHERE NOT is_top_10pct)
            AS other_90pct_average_revenue,
        MEDIAN(cumulative_total_revenue) FILTER (WHERE NOT is_top_10pct)
            AS other_90pct_median_revenue
    FROM eda_company_cumulative_revenue_rank
)
SELECT
    p.confirmed_company_profiles,
    p.activated_companies_through_cutoff,
    r.revenue_companies,
    r.top_10pct_companies,
    ROUND(100.0 * r.top_10pct_companies / r.revenue_companies, 2)
        AS share_of_revenue_companies_pct,
    ROUND(
        100.0 * r.top_10pct_companies
        / p.activated_companies_through_cutoff,
        2
    ) AS share_of_activated_companies_pct,
    ROUND(
        100.0 * r.top_10pct_companies / p.confirmed_company_profiles,
        2
    ) AS share_of_confirmed_profiles_pct,
    r.total_revenue,
    r.top_10pct_revenue,
    ROUND(100.0 * r.top_10pct_revenue / r.total_revenue, 2)
        AS top_10pct_revenue_share_pct,
    r.top_10pct_entry_revenue,
    r.top_10pct_average_revenue,
    r.top_10pct_median_revenue,
    r.other_90pct_average_revenue,
    r.other_90pct_median_revenue
FROM population p
CROSS JOIN revenue r;

-- Persona, initial-plan, and intersection profiles. The representation index is
-- segment share within the top decile divided by segment share in the complete
-- revenue-company population. Above 1 means overrepresented.
CREATE OR REPLACE TABLE eda_top10_revenue_companies_by_segment AS
WITH aggregated AS (
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
        COUNT(*) AS revenue_companies,
        COUNT(*) FILTER (WHERE is_top_10pct) AS top_10pct_companies,
        SUM(cumulative_total_revenue) AS segment_total_revenue,
        SUM(cumulative_total_revenue) FILTER (WHERE is_top_10pct)
            AS top_10pct_revenue
    FROM eda_company_cumulative_revenue_rank
    GROUP BY GROUPING SETS (
        (),
        (persona),
        (initial_subscription_group),
        (persona, initial_subscription_group)
    )
),
totals AS (
    SELECT
        revenue_companies AS all_revenue_companies,
        top_10pct_companies AS all_top_10pct_companies,
        top_10pct_revenue AS all_top_10pct_revenue
    FROM aggregated
    WHERE segment_level = 'overall'
)
SELECT
    a.*,
    ROUND(
        100.0 * a.top_10pct_companies / NULLIF(a.revenue_companies, 0),
        2
    ) AS segment_top_10pct_penetration_pct,
    ROUND(
        100.0 * a.top_10pct_companies / t.all_top_10pct_companies,
        2
    ) AS top_10pct_company_mix_pct,
    ROUND(
        100.0 * a.revenue_companies / t.all_revenue_companies,
        2
    ) AS base_revenue_company_mix_pct,
    ROUND(
        (a.top_10pct_companies::DOUBLE / t.all_top_10pct_companies)
        / NULLIF(
            a.revenue_companies::DOUBLE / t.all_revenue_companies,
            0
        ),
        2
    ) AS company_representation_index,
    ROUND(
        100.0 * COALESCE(a.top_10pct_revenue, 0)
        / NULLIF(a.segment_total_revenue, 0),
        2
    ) AS top_10pct_share_of_segment_revenue_pct,
    ROUND(
        100.0 * COALESCE(a.top_10pct_revenue, 0)
        / t.all_top_10pct_revenue,
        2
    ) AS share_of_all_top_10pct_revenue_pct
FROM aggregated a
CROSS JOIN totals t
ORDER BY
    segment_level,
    top_10pct_companies DESC,
    persona,
    initial_subscription_group;

CREATE OR REPLACE TABLE eda_top10_revenue_by_type AS
WITH totals AS (
    SELECT
        SUM(subscription_revenue) AS subscription_total,
        SUM(subscription_revenue) FILTER (WHERE is_top_10pct)
            AS subscription_top,
        SUM(interchange_revenue) AS interchange_total,
        SUM(interchange_revenue) FILTER (WHERE is_top_10pct)
            AS interchange_top,
        SUM(banking_fees) AS banking_fees_total,
        SUM(banking_fees) FILTER (WHERE is_top_10pct)
            AS banking_fees_top,
        SUM(deposit_interest_revenue) AS deposit_interest_total,
        SUM(deposit_interest_revenue) FILTER (WHERE is_top_10pct)
            AS deposit_interest_top,
        SUM(cumulative_total_revenue) AS total_revenue,
        SUM(cumulative_total_revenue) FILTER (WHERE is_top_10pct)
            AS total_revenue_top
    FROM eda_company_cumulative_revenue_rank
)
SELECT
    revenue_type,
    total_revenue,
    top_10pct_revenue,
    ROUND(100.0 * top_10pct_revenue / NULLIF(total_revenue, 0), 2)
        AS top_10pct_revenue_share_pct
FROM totals
UNPIVOT (
    (total_revenue, top_10pct_revenue) FOR revenue_type IN (
        (subscription_total, subscription_top) AS subscription,
        (interchange_total, interchange_top) AS interchange,
        (banking_fees_total, banking_fees_top) AS banking_fees,
        (deposit_interest_total, deposit_interest_top) AS deposit_interest,
        (total_revenue, total_revenue_top) AS total
    )
)
ORDER BY CASE revenue_type
    WHEN 'subscription' THEN 1
    WHEN 'interchange' THEN 2
    WHEN 'banking_fees' THEN 3
    WHEN 'deposit_interest' THEN 4
    ELSE 5
END;

-- Cumulative rankings naturally favor earlier activations because they have
-- more observed months. This diagnostic makes that exposure bias visible.
CREATE OR REPLACE TABLE eda_top10_revenue_by_activation_cohort AS
WITH cohort AS (
    SELECT
        DATE_TRUNC('month', c.activation_date)::DATE AS activation_month,
        COUNT(*) AS revenue_companies,
        COUNT(*) FILTER (WHERE r.is_top_10pct) AS top_10pct_companies,
        SUM(r.cumulative_total_revenue) AS cohort_total_revenue,
        SUM(r.cumulative_total_revenue) FILTER (WHERE r.is_top_10pct)
            AS top_10pct_revenue
    FROM eda_company_cumulative_revenue_rank r
    LEFT JOIN companies c USING (company_profile_id)
    GROUP BY DATE_TRUNC('month', c.activation_date)
),
totals AS (
    SELECT
        SUM(top_10pct_companies) AS all_top_10pct_companies,
        SUM(top_10pct_revenue) AS all_top_10pct_revenue
    FROM cohort
)
SELECT
    c.*,
    ROUND(
        100.0 * c.top_10pct_companies / NULLIF(c.revenue_companies, 0),
        2
    ) AS cohort_top_10pct_penetration_pct,
    ROUND(
        100.0 * c.top_10pct_companies / t.all_top_10pct_companies,
        2
    ) AS share_of_top_10pct_companies_pct,
    ROUND(
        100.0 * c.top_10pct_revenue / t.all_top_10pct_revenue,
        2
    ) AS share_of_top_10pct_revenue_pct
FROM cohort c
CROSS JOIN totals t
ORDER BY activation_month;

-- ============================================================
-- TENURE-CONTROLLED SENSITIVITY: CUMULATIVE REVENUE THROUGH AGE 3
-- ============================================================
-- Every eligible company has the same four-month revenue opportunity: ages
-- zero, one, two, and three. This removes the main exposure bias in the full
-- October-April cumulative ranking.

CREATE OR REPLACE TABLE eda_company_age3_revenue_rank AS
WITH age3_revenue AS (
    SELECT
        company_profile_id,
        persona,
        initial_subscription_group,
        activation_month,
        SUM(total_revenue) AS cumulative_revenue_through_age3
    FROM eda_company_cohort_month_state
    WHERE months_since_activation BETWEEN 0 AND 3
      AND activation_month
          <= (SELECT confirmed_end_month FROM analysis_parameters)
             - INTERVAL '3 months'
    GROUP BY
        company_profile_id,
        persona,
        initial_subscription_group,
        activation_month
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY
                cumulative_revenue_through_age3 DESC,
                company_profile_id
        ) AS revenue_rank,
        COUNT(*) OVER () AS eligible_company_population
    FROM age3_revenue
)
SELECT
    *,
    CEIL(0.10 * eligible_company_population)::BIGINT
        AS top_decile_company_count,
    revenue_rank <= CEIL(0.10 * eligible_company_population)
        AS is_top_10pct,
    CEIL(0.20 * eligible_company_population)::BIGINT
        AS top_20pct_company_count,
    revenue_rank <= CEIL(0.20 * eligible_company_population)
        AS is_top_20pct
FROM ranked
ORDER BY revenue_rank;

CREATE OR REPLACE TABLE eda_age3_top10_revenue_summary AS
SELECT
    COUNT(*) AS eligible_companies,
    COUNT(*) FILTER (WHERE is_top_10pct) AS top_10pct_companies,
    SUM(cumulative_revenue_through_age3) AS total_revenue_through_age3,
    SUM(cumulative_revenue_through_age3) FILTER (WHERE is_top_10pct)
        AS top_10pct_revenue_through_age3,
    ROUND(
        100.0 * SUM(cumulative_revenue_through_age3) FILTER (
            WHERE is_top_10pct
        ) / SUM(cumulative_revenue_through_age3),
        2
    ) AS top_10pct_revenue_share_pct,
    MIN(cumulative_revenue_through_age3) FILTER (WHERE is_top_10pct)
        AS top_10pct_entry_revenue
FROM eda_company_age3_revenue_rank;

CREATE OR REPLACE TABLE eda_age3_top10_revenue_by_segment AS
WITH aggregated AS (
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
        COUNT(*) AS eligible_companies,
        COUNT(*) FILTER (WHERE is_top_10pct) AS top_10pct_companies,
        SUM(cumulative_revenue_through_age3) AS segment_revenue,
        SUM(cumulative_revenue_through_age3) FILTER (WHERE is_top_10pct)
            AS top_10pct_revenue
    FROM eda_company_age3_revenue_rank
    GROUP BY GROUPING SETS (
        (),
        (persona),
        (initial_subscription_group),
        (persona, initial_subscription_group)
    )
),
totals AS (
    SELECT
        eligible_companies AS all_eligible_companies,
        top_10pct_companies AS all_top_10pct_companies,
        top_10pct_revenue AS all_top_10pct_revenue
    FROM aggregated
    WHERE segment_level = 'overall'
)
SELECT
    a.*,
    ROUND(
        100.0 * a.top_10pct_companies / NULLIF(a.eligible_companies, 0),
        2
    ) AS segment_top_10pct_penetration_pct,
    ROUND(
        100.0 * a.top_10pct_companies / t.all_top_10pct_companies,
        2
    ) AS top_10pct_company_mix_pct,
    ROUND(
        100.0 * a.eligible_companies / t.all_eligible_companies,
        2
    ) AS base_company_mix_pct,
    ROUND(
        (a.top_10pct_companies::DOUBLE / t.all_top_10pct_companies)
        / NULLIF(
            a.eligible_companies::DOUBLE / t.all_eligible_companies,
            0
        ),
        2
    ) AS company_representation_index,
    ROUND(
        100.0 * COALESCE(a.top_10pct_revenue, 0)
        / t.all_top_10pct_revenue,
        2
    ) AS share_of_all_top_10pct_revenue_pct
FROM aggregated a
CROSS JOIN totals t
ORDER BY
    segment_level,
    top_10pct_companies DESC,
    persona,
    initial_subscription_group;

-- Concentration curve for testing Pareto-style thresholds. Revenue is summed
-- with full stored precision; rounding is applied only to displayed shares.
CREATE OR REPLACE TABLE eda_revenue_concentration_curve AS
WITH thresholds AS (
    SELECT *
    FROM (VALUES (1), (5), (10), (20), (30), (50)) AS t(top_company_pct)
),
totals AS (
    SELECT
        COUNT(*) AS companies,
        SUM(cumulative_total_revenue) AS total_revenue
    FROM eda_company_cumulative_revenue_rank
)
SELECT
    t.top_company_pct,
    CEIL(t.top_company_pct / 100.0 * x.companies)::BIGINT
        AS included_companies,
    SUM(r.cumulative_total_revenue) FILTER (
        WHERE r.revenue_rank
              <= CEIL(t.top_company_pct / 100.0 * x.companies)
    ) AS included_revenue,
    ROUND(
        100.0 * SUM(r.cumulative_total_revenue) FILTER (
            WHERE r.revenue_rank
                  <= CEIL(t.top_company_pct / 100.0 * x.companies)
        ) / x.total_revenue,
        2
    ) AS cumulative_revenue_share_pct
FROM thresholds t
CROSS JOIN totals x
CROSS JOIN eda_company_cumulative_revenue_rank r
GROUP BY
    t.top_company_pct,
    x.companies,
    x.total_revenue
ORDER BY t.top_company_pct;

CREATE OR REPLACE TABLE eda_age3_revenue_concentration_curve AS
WITH thresholds AS (
    SELECT *
    FROM (VALUES (1), (5), (10), (20), (30), (50)) AS t(top_company_pct)
),
totals AS (
    SELECT
        COUNT(*) AS companies,
        SUM(cumulative_revenue_through_age3) AS total_revenue
    FROM eda_company_age3_revenue_rank
)
SELECT
    t.top_company_pct,
    CEIL(t.top_company_pct / 100.0 * x.companies)::BIGINT
        AS included_companies,
    SUM(r.cumulative_revenue_through_age3) FILTER (
        WHERE r.revenue_rank
              <= CEIL(t.top_company_pct / 100.0 * x.companies)
    ) AS included_revenue,
    ROUND(
        100.0 * SUM(r.cumulative_revenue_through_age3) FILTER (
            WHERE r.revenue_rank
                  <= CEIL(t.top_company_pct / 100.0 * x.companies)
        ) / x.total_revenue,
        2
    ) AS cumulative_revenue_share_pct
FROM thresholds t
CROSS JOIN totals x
CROSS JOIN eda_company_age3_revenue_rank r
GROUP BY
    t.top_company_pct,
    x.companies,
    x.total_revenue
ORDER BY t.top_company_pct;

CREATE OR REPLACE TABLE eda_revenue_pareto_threshold AS
WITH cumulative_full AS (
    SELECT
        revenue_rank,
        COUNT(*) OVER () AS company_population,
        cumulative_total_revenue AS entry_revenue,
        SUM(cumulative_total_revenue) OVER (
            ORDER BY revenue_rank
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(cumulative_total_revenue) OVER () AS cumulative_revenue_share
    FROM eda_company_cumulative_revenue_rank
),
full_threshold AS (
    SELECT *
    FROM cumulative_full
    WHERE cumulative_revenue_share >= 0.80
    ORDER BY revenue_rank
    LIMIT 1
),
cumulative_age3 AS (
    SELECT
        revenue_rank,
        COUNT(*) OVER () AS company_population,
        cumulative_revenue_through_age3 AS entry_revenue,
        SUM(cumulative_revenue_through_age3) OVER (
            ORDER BY revenue_rank
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / SUM(cumulative_revenue_through_age3) OVER ()
            AS cumulative_revenue_share
    FROM eda_company_age3_revenue_rank
),
age3_threshold AS (
    SELECT *
    FROM cumulative_age3
    WHERE cumulative_revenue_share >= 0.80
    ORDER BY revenue_rank
    LIMIT 1
)
SELECT
    'cumulative_through_april' AS analysis_view,
    revenue_rank AS companies_needed,
    company_population,
    ROUND(100.0 * revenue_rank / company_population, 2)
        AS company_share_needed_pct,
    ROUND(100.0 * cumulative_revenue_share, 2)
        AS achieved_revenue_share_pct,
    entry_revenue
FROM full_threshold
UNION ALL
SELECT
    'tenure_controlled_through_age3' AS analysis_view,
    revenue_rank AS companies_needed,
    company_population,
    ROUND(100.0 * revenue_rank / company_population, 2)
        AS company_share_needed_pct,
    ROUND(100.0 * cumulative_revenue_share, 2)
        AS achieved_revenue_share_pct,
    entry_revenue
FROM age3_threshold
ORDER BY analysis_view;

-- ============================================================
-- TOP 20% PRESENTATION VIEW
-- ============================================================

CREATE OR REPLACE TABLE eda_top20_revenue_concentration_summary AS
WITH population AS (
    SELECT
        COUNT(*) FILTER (
            WHERE company_signup_at::DATE
                  < (SELECT provisional_month FROM analysis_parameters)
        ) AS confirmed_company_profiles,
        COUNT(*) FILTER (
            WHERE activation_date IS NOT NULL
              AND DATE_TRUNC('month', activation_date)::DATE
                  <= (SELECT confirmed_end_month FROM analysis_parameters)
        ) AS activated_companies_through_cutoff
    FROM companies
),
revenue AS (
    SELECT
        COUNT(*) AS revenue_companies,
        COUNT(*) FILTER (WHERE is_top_20pct) AS top_20pct_companies,
        SUM(cumulative_total_revenue) AS total_revenue,
        SUM(cumulative_total_revenue) FILTER (WHERE is_top_20pct)
            AS top_20pct_revenue,
        MIN(cumulative_total_revenue) FILTER (WHERE is_top_20pct)
            AS top_20pct_entry_revenue,
        AVG(cumulative_total_revenue) FILTER (WHERE is_top_20pct)
            AS top_20pct_average_revenue,
        MEDIAN(cumulative_total_revenue) FILTER (WHERE is_top_20pct)
            AS top_20pct_median_revenue,
        AVG(cumulative_total_revenue) FILTER (WHERE NOT is_top_20pct)
            AS other_80pct_average_revenue,
        MEDIAN(cumulative_total_revenue) FILTER (WHERE NOT is_top_20pct)
            AS other_80pct_median_revenue
    FROM eda_company_cumulative_revenue_rank
)
SELECT
    p.confirmed_company_profiles,
    p.activated_companies_through_cutoff,
    r.revenue_companies,
    r.top_20pct_companies,
    ROUND(100.0 * r.top_20pct_companies / r.revenue_companies, 2)
        AS share_of_revenue_companies_pct,
    ROUND(
        100.0 * r.top_20pct_companies
        / p.activated_companies_through_cutoff,
        2
    ) AS share_of_activated_companies_pct,
    ROUND(
        100.0 * r.top_20pct_companies / p.confirmed_company_profiles,
        2
    ) AS share_of_confirmed_profiles_pct,
    r.total_revenue,
    r.top_20pct_revenue,
    ROUND(100.0 * r.top_20pct_revenue / r.total_revenue, 2)
        AS top_20pct_revenue_share_pct,
    r.top_20pct_entry_revenue,
    r.top_20pct_average_revenue,
    r.top_20pct_median_revenue,
    r.other_80pct_average_revenue,
    r.other_80pct_median_revenue
FROM population p
CROSS JOIN revenue r;

CREATE OR REPLACE TABLE eda_top20_revenue_companies_by_segment AS
WITH aggregated AS (
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
        COUNT(*) AS revenue_companies,
        COUNT(*) FILTER (WHERE is_top_20pct) AS top_20pct_companies,
        SUM(cumulative_total_revenue) AS segment_total_revenue,
        SUM(cumulative_total_revenue) FILTER (WHERE is_top_20pct)
            AS top_20pct_revenue
    FROM eda_company_cumulative_revenue_rank
    GROUP BY GROUPING SETS (
        (),
        (persona),
        (initial_subscription_group),
        (persona, initial_subscription_group)
    )
),
totals AS (
    SELECT
        revenue_companies AS all_revenue_companies,
        top_20pct_companies AS all_top_20pct_companies,
        top_20pct_revenue AS all_top_20pct_revenue
    FROM aggregated
    WHERE segment_level = 'overall'
)
SELECT
    a.*,
    ROUND(
        100.0 * a.top_20pct_companies / NULLIF(a.revenue_companies, 0),
        2
    ) AS segment_top_20pct_penetration_pct,
    ROUND(
        100.0 * a.top_20pct_companies / t.all_top_20pct_companies,
        2
    ) AS top_20pct_company_mix_pct,
    ROUND(
        100.0 * a.revenue_companies / t.all_revenue_companies,
        2
    ) AS base_revenue_company_mix_pct,
    ROUND(
        (a.top_20pct_companies::DOUBLE / t.all_top_20pct_companies)
        / NULLIF(
            a.revenue_companies::DOUBLE / t.all_revenue_companies,
            0
        ),
        2
    ) AS company_representation_index,
    ROUND(
        100.0 * COALESCE(a.top_20pct_revenue, 0)
        / NULLIF(a.segment_total_revenue, 0),
        2
    ) AS top_20pct_share_of_segment_revenue_pct,
    ROUND(
        100.0 * COALESCE(a.top_20pct_revenue, 0)
        / t.all_top_20pct_revenue,
        2
    ) AS share_of_all_top_20pct_revenue_pct
FROM aggregated a
CROSS JOIN totals t
ORDER BY
    segment_level,
    top_20pct_companies DESC,
    persona,
    initial_subscription_group;

CREATE OR REPLACE TABLE eda_top20_revenue_by_type AS
WITH totals AS (
    SELECT
        SUM(subscription_revenue) AS subscription_total,
        SUM(subscription_revenue) FILTER (WHERE is_top_20pct)
            AS subscription_top,
        SUM(interchange_revenue) AS interchange_total,
        SUM(interchange_revenue) FILTER (WHERE is_top_20pct)
            AS interchange_top,
        SUM(banking_fees) AS banking_fees_total,
        SUM(banking_fees) FILTER (WHERE is_top_20pct)
            AS banking_fees_top,
        SUM(deposit_interest_revenue) AS deposit_interest_total,
        SUM(deposit_interest_revenue) FILTER (WHERE is_top_20pct)
            AS deposit_interest_top,
        SUM(cumulative_total_revenue) AS total_revenue,
        SUM(cumulative_total_revenue) FILTER (WHERE is_top_20pct)
            AS total_revenue_top
    FROM eda_company_cumulative_revenue_rank
)
SELECT
    revenue_type,
    total_revenue,
    top_20pct_revenue,
    ROUND(100.0 * top_20pct_revenue / NULLIF(total_revenue, 0), 2)
        AS top_20pct_revenue_share_pct
FROM totals
UNPIVOT (
    (total_revenue, top_20pct_revenue) FOR revenue_type IN (
        (subscription_total, subscription_top) AS subscription,
        (interchange_total, interchange_top) AS interchange,
        (banking_fees_total, banking_fees_top) AS banking_fees,
        (deposit_interest_total, deposit_interest_top) AS deposit_interest,
        (total_revenue, total_revenue_top) AS total
    )
)
ORDER BY CASE revenue_type
    WHEN 'subscription' THEN 1
    WHEN 'interchange' THEN 2
    WHEN 'banking_fees' THEN 3
    WHEN 'deposit_interest' THEN 4
    ELSE 5
END;

CREATE OR REPLACE TABLE eda_top20_revenue_by_activation_cohort AS
WITH cohort AS (
    SELECT
        DATE_TRUNC('month', c.activation_date)::DATE AS activation_month,
        COUNT(*) AS revenue_companies,
        COUNT(*) FILTER (WHERE r.is_top_20pct) AS top_20pct_companies,
        SUM(r.cumulative_total_revenue) AS cohort_total_revenue,
        SUM(r.cumulative_total_revenue) FILTER (WHERE r.is_top_20pct)
            AS top_20pct_revenue
    FROM eda_company_cumulative_revenue_rank r
    LEFT JOIN companies c USING (company_profile_id)
    GROUP BY DATE_TRUNC('month', c.activation_date)
),
totals AS (
    SELECT
        SUM(top_20pct_companies) AS all_top_20pct_companies,
        SUM(top_20pct_revenue) AS all_top_20pct_revenue
    FROM cohort
)
SELECT
    c.*,
    ROUND(
        100.0 * c.top_20pct_companies / NULLIF(c.revenue_companies, 0),
        2
    ) AS cohort_top_20pct_penetration_pct,
    ROUND(
        100.0 * c.top_20pct_companies / t.all_top_20pct_companies,
        2
    ) AS share_of_top_20pct_companies_pct,
    ROUND(
        100.0 * c.top_20pct_revenue / t.all_top_20pct_revenue,
        2
    ) AS share_of_top_20pct_revenue_pct
FROM cohort c
CROSS JOIN totals t
ORDER BY activation_month;

CREATE OR REPLACE TABLE eda_age3_top20_revenue_summary AS
SELECT
    COUNT(*) AS eligible_companies,
    COUNT(*) FILTER (WHERE is_top_20pct) AS top_20pct_companies,
    SUM(cumulative_revenue_through_age3) AS total_revenue_through_age3,
    SUM(cumulative_revenue_through_age3) FILTER (WHERE is_top_20pct)
        AS top_20pct_revenue_through_age3,
    ROUND(
        100.0 * SUM(cumulative_revenue_through_age3) FILTER (
            WHERE is_top_20pct
        ) / SUM(cumulative_revenue_through_age3),
        2
    ) AS top_20pct_revenue_share_pct,
    MIN(cumulative_revenue_through_age3) FILTER (WHERE is_top_20pct)
        AS top_20pct_entry_revenue
FROM eda_company_age3_revenue_rank;

CREATE OR REPLACE TABLE eda_age3_top20_revenue_by_segment AS
WITH aggregated AS (
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
        COUNT(*) AS eligible_companies,
        COUNT(*) FILTER (WHERE is_top_20pct) AS top_20pct_companies,
        SUM(cumulative_revenue_through_age3) AS segment_revenue,
        SUM(cumulative_revenue_through_age3) FILTER (WHERE is_top_20pct)
            AS top_20pct_revenue
    FROM eda_company_age3_revenue_rank
    GROUP BY GROUPING SETS (
        (),
        (persona),
        (initial_subscription_group),
        (persona, initial_subscription_group)
    )
),
totals AS (
    SELECT
        eligible_companies AS all_eligible_companies,
        top_20pct_companies AS all_top_20pct_companies,
        top_20pct_revenue AS all_top_20pct_revenue
    FROM aggregated
    WHERE segment_level = 'overall'
)
SELECT
    a.*,
    ROUND(
        100.0 * a.top_20pct_companies / NULLIF(a.eligible_companies, 0),
        2
    ) AS segment_top_20pct_penetration_pct,
    ROUND(
        100.0 * a.top_20pct_companies / t.all_top_20pct_companies,
        2
    ) AS top_20pct_company_mix_pct,
    ROUND(
        100.0 * a.eligible_companies / t.all_eligible_companies,
        2
    ) AS base_company_mix_pct,
    ROUND(
        (a.top_20pct_companies::DOUBLE / t.all_top_20pct_companies)
        / NULLIF(
            a.eligible_companies::DOUBLE / t.all_eligible_companies,
            0
        ),
        2
    ) AS company_representation_index,
    ROUND(
        100.0 * COALESCE(a.top_20pct_revenue, 0)
        / t.all_top_20pct_revenue,
        2
    ) AS share_of_all_top_20pct_revenue_pct
FROM aggregated a
CROSS JOIN totals t
ORDER BY
    segment_level,
    top_20pct_companies DESC,
    persona,
    initial_subscription_group;
