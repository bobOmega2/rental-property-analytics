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
-- How much rent came in vs how much we spent each month.
-- Net profit = income - expenses. Negative = loss that month.
--
-- Structure: two CTEs (named subqueries) aggregated independently,
-- then joined on month. Income and expenses share no FK — time
-- is the only link between them.
--
-- Why two CTEs instead of one query?
--   Income lives in payments, expenses in expenses. No FK connects
--   them. We aggregate each side to the month level first, then
--   join the two monthly summaries together.
--
-- Why FULL OUTER JOIN?
--   A vacant month may have expenses but no rent (LEFT JOIN drops it).
--   A month with rent but zero expenses would be dropped by RIGHT JOIN.
--   FULL OUTER keeps every month that appears in either table.
--
-- Why COALESCE(..., 0)?
--   When one side has no data for a month, the JOIN produces NULL.
--   NULL - 500 = NULL (math breaks). COALESCE replaces NULL with 0.
-- ============================================

WITH monthly_income AS (

    -- Sum all confirmed rent collected, grouped by month.
    -- DATE_TRUNC collapses any date to the 1st of its month
    -- so GROUP BY treats all payments in January as one group.
    -- e.g. 2024-01-17 → 2024-01-01, 2024-01-28 → 2024-01-01
    -- Exclude 'missed' payments — no money was received for those.
    -- Both 'on_time' and 'late' mean the payment arrived (just when).
    -- Cash basis: only count money actually received.
    SELECT
        DATE_TRUNC('month', payment_date) AS month,
        SUM(amount)                       AS total_income
    FROM payments
    WHERE status IN ('on_time', 'late')
    GROUP BY 1

),

monthly_expenses AS (

    -- Sum all expenses, grouped by month.
    -- No status filter needed — every row in expenses is a confirmed spend.
    -- Includes both opex and capex (see Query 4 for the breakdown).
    SELECT
        DATE_TRUNC('month', expense_date) AS month,
        SUM(amount)                       AS total_expenses
    FROM expenses
    GROUP BY 1

)

SELECT
    -- COALESCE(i.month, e.month): when a month only exists on one side,
    -- the other side's month column is NULL after the FULL OUTER JOIN.
    -- We take whichever side is non-NULL to get the actual month value.
    COALESCE(i.month, e.month)                                        AS month,

    COALESCE(i.total_income, 0)                                       AS total_income,
    COALESCE(e.total_expenses, 0)                                     AS total_expenses,

    -- Net profit: positive = profitable month, negative = loss
    COALESCE(i.total_income, 0) - COALESCE(e.total_expenses, 0)      AS net_profit

FROM       monthly_income    AS i
FULL OUTER JOIN monthly_expenses AS e ON i.month = e.month

-- Most recent month last — easier to read as a time series
ORDER BY month;


-- ============================================
-- QUERY 2: Payment Delinquency by Tenant
-- ============================================
-- Which tenants pay late, how often, and are we collecting
-- the late fees we charge?
--
-- Useful for lease renewal decisions — a tenant with a high
-- late rate and low fee collection rate is a red flag.
--
-- JOIN chain: payments → leases → tenants
--   payments has lease_id, leases has tenant_id, tenants has name.
--   Two JOINs needed to get from a payment row to a tenant name.
--   Regular JOIN (inner) is correct here — every payment has a lease,
--   every lease has a tenant. No missing rows to worry about.
--
-- Why FILTER instead of CASE WHEN?
--   COUNT(*) FILTER (WHERE status = 'late') counts only late rows.
--   Cleaner than SUM(CASE WHEN status = 'late' THEN 1 ELSE 0 END).
--
-- Why NULLIF(total_charged, 0)?
--   If a tenant was never charged a late fee, dividing by 0 crashes
--   the query. NULLIF turns 0 into NULL — dividing by NULL returns
--   NULL instead of an error. Shows up as blank in the output.
-- ============================================

SELECT
    -- Tenant name — concatenated from first + last
    t.first_name || ' ' || t.last_name          AS tenant,

    -- Total payments on record for this tenant
    COUNT(*)                                     AS total_payments,

    -- How many of those payments were late
    COUNT(*) FILTER (WHERE p.status = 'late')   AS late_payments,

    -- Late rate as a percentage: late / total * 100, rounded to 1 decimal
    ROUND(
        COUNT(*) FILTER (WHERE p.status = 'late')
        * 100.0 / COUNT(*),
    1)                                           AS late_rate_pct,

    -- Total late fees assessed across all late payments
    COALESCE(SUM(p.late_fee_charged), 0)         AS late_fees_charged,

    -- Total late fees actually collected (waived fees show as 0 in data)
    COALESCE(SUM(p.late_fee_collected), 0)       AS late_fees_collected,

    -- Fee collection rate: collected / charged * 100
    -- NULLIF prevents divide-by-zero for tenants never charged a fee
    ROUND(
        COALESCE(SUM(p.late_fee_collected), 0)
        * 100.0 / NULLIF(COALESCE(SUM(p.late_fee_charged), 0), 0),
    1)                                           AS fee_collection_rate_pct

FROM payments   AS p
JOIN leases     AS l ON p.lease_id  = l.lease_id
JOIN tenants    AS t ON l.tenant_id = t.tenant_id

GROUP BY t.tenant_id, t.first_name, t.last_name

-- Worst offenders first (most late payments at the top)
ORDER BY late_payments DESC, late_rate_pct DESC;


-- ============================================
-- QUERY 3: Vacancy Analysis
-- ============================================
-- For each unit, how long did it sit empty between leases,
-- and how much rent did we lose during that gap?
--
-- Vacancy doesn't appear in the expenses table — it's lost
-- revenue, not a cost. This query makes it visible.
--
-- How it works:
--   1. CTE adds a next_lease_start column to each lease row
--      using LEAD() — a window function that peeks at the
--      next row's value without collapsing rows like GROUP BY.
--   2. Outer query calculates the gap and estimates lost rent.
--
-- LEAD() syntax:
--   LEAD(col) OVER (PARTITION BY unit_id ORDER BY start_date)
--   PARTITION BY unit_id : reset "next row" logic per unit so
--     leases from different units don't bleed into each other.
--   ORDER BY start_date  : defines what "next" means
--     (next lease chronologically, not by lease_id).
--
-- Why filter WHERE next_lease_start IS NOT NULL?
--   The last (or only) active lease per unit has no next lease —
--   LEAD() returns NULL. No next lease = no gap to measure.
-- ============================================

WITH lease_gaps AS (

    SELECT
        u.unit_label,
        l.lease_id,
        l.end_date                                           AS lease_end,

        -- LEAD peeks at the next lease's start_date for this unit.
        -- The gap between this lease's end and the next lease's start
        -- is the vacancy period.
        LEAD(l.start_date) OVER (
            PARTITION BY l.unit_id
            ORDER BY l.start_date
        )                                                    AS next_lease_start,

        -- Monthly rent of the ending lease — used to estimate daily loss.
        -- We use this lease's rent, not the next one's, since it represents
        -- the rate the unit was renting at when it became vacant.
        l.monthly_rent

    FROM leases AS l
    JOIN units  AS u ON l.unit_id = u.unit_id

)

SELECT
    unit_label,

    lease_end,
    next_lease_start,

    -- Vacancy duration in days: subtract two dates → integer (days)
    (next_lease_start - lease_end)                           AS vacancy_days,

    -- Estimated lost rent: daily rate × vacant days
    -- monthly_rent / 30.0 = daily rate (30.0 not 30 to avoid integer division)
    ROUND(
        (next_lease_start - lease_end) * (monthly_rent / 30.0),
    2)                                                       AS est_lost_rent

FROM lease_gaps

-- Exclude rows where there is no next lease (currently occupied or no history)
WHERE next_lease_start IS NOT NULL

-- Longest vacancies first
ORDER BY vacancy_days DESC;


-- ============================================
-- QUERY 4: Expense Breakdown by Category
-- ============================================
-- Total spending per expense category, split into OpEx vs CapEx.
-- OpEx = deducted in full this tax year (CRA T776 line 9270).
-- CapEx = capital purchase, NOT deducted now — depreciated via CCA.
--
-- Why does the opex/capex split matter?
--   A P&L that lumps them together overstates expenses in any year
--   with a major capital purchase (e.g. new appliance, roof).
--   This query shows the tax-correct view of where money went.
--
-- Why FILTER instead of CASE WHEN?
--   SUM(amount) FILTER (WHERE expense_class = 'opex') is cleaner
--   than SUM(CASE WHEN expense_class = 'opex' THEN amount ELSE 0 END).
--   Same result, more readable. CASE WHEN is only needed when you
--   want to return different computed values, not just filter.
--
-- Why HAVING instead of WHERE?
--   HAVING filters after GROUP BY — it can see aggregated values.
--   WHERE runs before GROUP BY and can't reference SUM(amount).
--   We use it to exclude categories with zero total spend.
-- ============================================

SELECT
    category,

    -- Total spend for this category (opex + capex combined)
    SUM(amount)                                                    AS total_spent,

    -- OpEx portion: operating expenses deductible in full this year
    COALESCE(SUM(amount) FILTER (WHERE expense_class = 'opex'), 0) AS total_opex,

    -- CapEx portion: capital expenditures depreciated via CCA over years
    COALESCE(SUM(amount) FILTER (WHERE expense_class = 'capex'), 0) AS total_capex,

    -- OpEx as a percentage of total spend in this category
    ROUND(
        COALESCE(SUM(amount) FILTER (WHERE expense_class = 'opex'), 0)
        * 100.0 / SUM(amount),
    1)                                                             AS opex_pct

FROM expenses

GROUP BY category

-- Exclude any category with no recorded expenses
HAVING SUM(amount) > 0

-- Highest spend categories first
ORDER BY total_spent DESC;


-- ============================================
-- QUERY 5: Rent Roll (Current Snapshot)
-- ============================================
-- Who is in each unit right now, what are they paying,
-- and when does their lease expire?
--
-- A rent roll is a standard landlord document — banks and
-- investors use it to assess portfolio stability at a glance.
--
-- Only active leases are included (status = 'active').
-- Expired and terminated leases are historical, not current state.
--
-- JOIN chain: units → leases → tenants
--   units is the anchor — we want one row per unit.
--   leases connects units to tenants.
--   tenants provides the name.
--
-- Why (CURRENT_DATE - l.start_date) / 30?
--   Subtracting two dates returns integer days. Dividing by 30
--   approximates months. Good enough for "how long has this
--   tenant been here" — no financial calculation depends on it.
--   See Query 3 for when exact day counts actually matter.
-- ============================================

SELECT
    u.unit_label,
    u.unit_type,

    -- Tenant full name
    t.first_name || ' ' || t.last_name             AS tenant,

    -- Rent being charged under this lease
    -- Stored on leases (not units) to preserve historical accuracy
    l.monthly_rent,

    l.start_date                                   AS lease_start,
    l.end_date                                     AS lease_end,

    -- How long the tenant has been in the unit, in approximate months
    (CURRENT_DATE - l.start_date) / 30             AS months_tenanted,

    -- Security deposit on file for this lease
    l.security_deposit

FROM units   AS u
JOIN leases  AS l ON u.unit_id    = l.unit_id
JOIN tenants AS t ON l.tenant_id  = t.tenant_id

-- Active leases only — this is a current snapshot, not history
WHERE l.status = 'active'

-- Sort by unit label for easy reading
ORDER BY u.unit_label;


-- ============================================
-- QUERY 6: Year-over-Year Revenue Comparison
-- ============================================
-- How did 2024 income, expenses, and net profit compare to 2025?
--
-- This is the portfolio-level summary — one row per year with
-- income, expenses, net profit, and YoY change all in one view.
--
-- No new concepts — same SUM + FILTER pattern as Query 4, but
-- applied to years instead of expense categories.
--
-- EXTRACT(year FROM date) — pulls just the year as a number.
--   Similar to DATE_TRUNC but returns a number (2024, 2025)
--   instead of a truncated date (2024-01-01).
--   Used here to GROUP BY year and to pivot into year columns.
--
-- Why two CTEs?
--   Same reason as Query 1 — income and expenses are in separate
--   tables with no FK. Aggregate each independently, then join on year.
--
-- Note: 2026 is excluded (only Jan-Feb data, not a full year).
-- ============================================

WITH yearly_income AS (

    -- Total rent collected per year, excluding missed payments
    SELECT
        EXTRACT(year FROM payment_date)  AS year,
        SUM(amount)                      AS total_income
    FROM payments
    WHERE status IN ('on_time', 'late')
      AND EXTRACT(year FROM payment_date) IN (2024, 2025)
    GROUP BY 1

),

yearly_expenses AS (

    -- Total expenses per year, split into opex and capex
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

    -- Net profit = income minus all expenses (opex + capex)
    i.total_income - e.total_expenses                               AS net_profit,

    -- YoY income change vs previous year
    -- LAG() looks at the previous row's value — same family as LEAD()
    -- but looks backwards instead of forwards.
    -- OVER (ORDER BY i.year) defines row order: previous = prior year.
    ROUND(
        (i.total_income - LAG(i.total_income) OVER (ORDER BY i.year))
        * 100.0 / LAG(i.total_income) OVER (ORDER BY i.year),
    1)                                                              AS income_yoy_pct

FROM yearly_income    AS i
JOIN yearly_expenses  AS e ON i.year = e.year

ORDER BY i.year;
