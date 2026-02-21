-- ============================================
-- Rental Property Analytics - Analysis Queries
-- ============================================
-- All queries run against the Supabase PostgreSQL database.
-- Amounts in CAD. Cash basis accounting (income when received,
-- expenses when paid).
-- ============================================


-- ============================================
-- QUERY 1: Monthly Cash Flow
-- ============================================
-- How much came in vs went out each month.
-- Income (payments) and expenses are in separate tables with no FK,
-- so we sum each side by month first (CTEs), then FULL OUTER JOIN.
-- FULL OUTER because a vacant month might have expenses but no income.
-- COALESCE(..., 0) so NULL from the join doesn't break the math.
-- ============================================

WITH monthly_income AS (

    -- DATE_TRUNC('month', ...) collapses all dates in a month to the 1st.
    -- skip 'missed' — no money arrived for those.
    SELECT
        DATE_TRUNC('month', payment_date) AS month,
        SUM(amount)                       AS total_income
    FROM payments
    WHERE status IN ('on_time', 'late')
    GROUP BY 1

),

monthly_expenses AS (

    -- no filter needed — every row in expenses is a confirmed spend
    SELECT
        DATE_TRUNC('month', expense_date) AS month,
        SUM(amount)                       AS total_expenses
    FROM expenses
    GROUP BY 1

)

SELECT
    -- after a FULL OUTER JOIN, month is NULL on whichever side had no data
    COALESCE(i.month, e.month)                                        AS month,

    COALESCE(i.total_income, 0)                                       AS total_income,
    COALESCE(e.total_expenses, 0)                                     AS total_expenses,
    COALESCE(i.total_income, 0) - COALESCE(e.total_expenses, 0)      AS net_profit

FROM       monthly_income    AS i
FULL OUTER JOIN monthly_expenses AS e ON i.month = e.month

ORDER BY month;


-- ============================================
-- QUERY 2: Payment Delinquency by Tenant
-- ============================================
-- Which tenants pay late, how often, and are we collecting the fees?
-- Useful for lease renewal decisions — high late rate + low fee collection = red flag.
-- JOIN chain: payments → leases → tenants (two JOINs to get from payment to name).
-- NULLIF(total_charged, 0) avoids div-by-zero for tenants never charged a fee.
-- ============================================

SELECT
    t.first_name || ' ' || t.last_name          AS tenant,
    COUNT(*)                                     AS total_payments,
    COUNT(*) FILTER (WHERE p.status = 'late')   AS late_payments,
    ROUND(
        COUNT(*) FILTER (WHERE p.status = 'late')
        * 100.0 / COUNT(*),
    1)                                           AS late_rate_pct,
    COALESCE(SUM(p.late_fee_charged), 0)         AS late_fees_charged,
    COALESCE(SUM(p.late_fee_collected), 0)       AS late_fees_collected,
    -- NULLIF prevents div-by-zero for tenants never charged a fee
    ROUND(
        COALESCE(SUM(p.late_fee_collected), 0)
        * 100.0 / NULLIF(COALESCE(SUM(p.late_fee_charged), 0), 0),
    1)                                           AS fee_collection_rate_pct

FROM payments   AS p
JOIN leases     AS l ON p.lease_id  = l.lease_id
JOIN tenants    AS t ON l.tenant_id = t.tenant_id

GROUP BY t.tenant_id, t.first_name, t.last_name

ORDER BY late_payments DESC, late_rate_pct DESC;


-- ============================================
-- QUERY 3: Vacancy Analysis
-- ============================================
-- How long did each unit sit empty between leases, and what did it cost?
-- Vacancy doesn't appear in expenses — it's lost revenue. This query makes it visible.
-- LEAD() peeks at the next lease's start_date per unit — that gap is the vacancy.
-- PARTITION BY unit_id keeps each unit's lease history separate.
-- WHERE next_lease_start IS NOT NULL excludes active leases (no next lease yet).
-- ============================================

WITH lease_gaps AS (

    SELECT
        u.unit_label,
        l.lease_id,
        l.end_date                                           AS lease_end,

        -- next lease's start_date for this unit — the gap between this and lease_end is the vacancy
        LEAD(l.start_date) OVER (
            PARTITION BY l.unit_id
            ORDER BY l.start_date
        )                                                    AS next_lease_start,

        l.monthly_rent

    FROM leases AS l
    JOIN units  AS u ON l.unit_id = u.unit_id

)

SELECT
    unit_label,

    lease_end,
    next_lease_start,

    (next_lease_start - lease_end)                           AS vacancy_days,

    -- 30.0 not 30 so we don't get integer division on the daily rate
    ROUND(
        (next_lease_start - lease_end) * (monthly_rent / 30.0),
    2)                                                       AS est_lost_rent

FROM lease_gaps

WHERE next_lease_start IS NOT NULL

ORDER BY vacancy_days DESC;


-- ============================================
-- QUERY 4: Expense Breakdown by Category
-- ============================================
-- Total spending per category, split opex vs capex.
-- OpEx = deductible in full this year. CapEx = depreciated via CCA over years.
-- Mixing them together overstates expenses in any year with a big capital purchase.
-- HAVING filters after GROUP BY so we can check the aggregated total.
-- ============================================

SELECT
    category,

    SUM(amount)                                                    AS total_spent,
    COALESCE(SUM(amount) FILTER (WHERE expense_class = 'opex'), 0) AS total_opex,
    COALESCE(SUM(amount) FILTER (WHERE expense_class = 'capex'), 0) AS total_capex,
    ROUND(
        COALESCE(SUM(amount) FILTER (WHERE expense_class = 'opex'), 0)
        * 100.0 / SUM(amount),
    1)                                                             AS opex_pct

FROM expenses

GROUP BY category

HAVING SUM(amount) > 0

ORDER BY total_spent DESC;


-- ============================================
-- QUERY 5: Rent Roll (Current Snapshot)
-- ============================================
-- Who's in each unit right now, what are they paying, when does it end?
-- A rent roll is a standard landlord doc — banks and investors use it to assess stability.
-- monthly_rent lives on leases (not units) so rent history is accurate across renewals.
-- ============================================

SELECT
    u.unit_label,
    u.unit_type,

    t.first_name || ' ' || t.last_name             AS tenant,
    l.monthly_rent,
    l.start_date                                   AS lease_start,
    l.end_date                                     AS lease_end,
    -- approximate months — date subtraction gives days, /30 is close enough here
    (CURRENT_DATE - l.start_date) / 30             AS months_tenanted,
    l.security_deposit

FROM units   AS u
JOIN leases  AS l ON u.unit_id    = l.unit_id
JOIN tenants AS t ON l.tenant_id  = t.tenant_id

WHERE l.status = 'active'

ORDER BY u.unit_label;


-- ============================================
-- QUERY 6: Year-over-Year Revenue Comparison
-- ============================================
-- How did 2024 compare to 2025? 2026 excluded — only Jan-Feb, not a full year.
-- Same two-CTE pattern as Q1 since income and expenses are in separate tables.
-- LAG() looks at the previous row's value — same window function family as LEAD() from Q3.
-- ============================================

WITH yearly_income AS (

    SELECT
        EXTRACT(year FROM payment_date)  AS year,
        SUM(amount)                      AS total_income
    FROM payments
    WHERE status IN ('on_time', 'late')
      AND EXTRACT(year FROM payment_date) IN (2024, 2025)
    GROUP BY 1

),

yearly_expenses AS (

    SELECT
        EXTRACT(year FROM expense_date)                               AS year,
        SUM(amount)                                                   AS total_expenses,
        COALESCE(SUM(amount) FILTER (WHERE expense_class = 'opex'), 0) AS total_opex,
        COALESCE(SUM(amount) FILTER (WHERE expense_class = 'capex'), 0) AS total_capex
    FROM expenses
    WHERE EXTRACT(year FROM expense_date) IN (2024, 2025)
    GROUP BY 1

)

SELECT
    i.year,
    i.total_income,
    e.total_expenses,
    e.total_opex,
    e.total_capex,
    i.total_income - e.total_expenses                               AS net_profit,

    -- LAG() looks at the prior row (previous year) — same family as LEAD() from Q3
    ROUND(
        (i.total_income - LAG(i.total_income) OVER (ORDER BY i.year))
        * 100.0 / LAG(i.total_income) OVER (ORDER BY i.year),
    1)                                                              AS income_yoy_pct

FROM yearly_income    AS i
JOIN yearly_expenses  AS e ON i.year = e.year

ORDER BY i.year;
