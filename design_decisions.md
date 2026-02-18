# Rental Property Analytics — Design Decisions

Concise record of key design choices and rationale.

---

## Schema Design

**Normalized, not flat**
Separate tables for properties, units, tenants, leases, payments, expenses, assets connected by foreign keys. Avoids data duplication and makes it possible to query at any level (property, unit, tenant, month) without restructuring. Follows 3NF.

**monthly_rent stored on both units and leases**
`units.monthly_rent` = current listed rate. `leases.monthly_rent` = rate actually agreed. Preserves historical accuracy when rent changes between tenants without overwriting the unit's current rate.

**expenses.unit_id is nullable**
`NULL` = property-wide cost (tax, insurance). Non-NULL = unit-specific cost (R1 plumbing repair). Allows expense slicing at both levels with a single table.

**No separate income table**
`payments` IS the income ledger. Every rent payment is an income event, traceable back to unit and tenant via `leases`. A separate income table would only be needed for non-rent revenue sources (parking, laundry), which don't exist here.

---

## Accounting Design

**Cash basis, not double-entry bookkeeping**
This is an analytics system, not a bookkeeping system. Double-entry (debits/credits) solves a bookkeeping problem — detecting errors in a manual ledger. SQL aggregations don't need that self-balancing mechanism. Cash basis: record income when received, expenses when paid. Standard for small Canadian landlords and accepted by the CRA.

**expense_class: OpEx vs CapEx (CRA T776)**
Critical accounting distinction for Form T776 (Statement of Real Estate Rentals):
- OpEx: deducted fully in the year incurred (repairs, management, insurance, property tax)
- CapEx: creates an asset; deducted via CCA (depreciation) over years — NOT in the year of purchase

Without this, a $680 refrigerator or $12,000 furnace overstates expenses in the purchase year and understates them in all subsequent years. Taxable income is wrong.

**assets table with CCA classes**
Tracks capital assets using Canada's CCA (Capital Cost Allowance) system per CRA Guide T4036:
- Class 1 (4% declining balance): the building
- Class 8 (20% declining balance): appliances, equipment
- Declining balance means each year's depreciation is applied to the remaining book value (UCC), not the original cost
- Half-year rule applies in the year of acquisition

Enables queries that calculate annual CCA deductions and UCC — directly usable for T776 reporting.

**Security deposit lifecycle on leases**
Deposits collected are a liability (money owed back to the tenant). Tracking only the amount collected is incomplete. Added: `deposit_returned_date`, `deposit_returned_amount`, `deposit_deductions`, `deposit_deduction_reason` to capture the full resolution. Michael Okafor's deposit was fully withheld for missed rent; David Kim's was returned in full.

**No chart of account codes**
The `category` column on expenses (property_tax, insurance, management, etc.) already provides the grouping needed for P&L analysis. Numeric account codes (4100, 5200) are useful in bookkeeping software for human data entry — in a SQL analytics system, named categories are cleaner and more readable in queries.

---

## Query Design

**Schema vs query: the rule**
- Change the schema when a *fact about the world* is missing from the data entirely (e.g., whether an expense is OpEx or CapEx — that fact didn't exist anywhere).
- Handle in a query when the data exists but needs to be shaped differently (e.g., allocating property tax across 8 units — the amount is there, the math is in the query).

**SQL-first, Python for delivery only**
All aggregation, filtering, and business logic is written in SQL. Python (`psycopg2` + `pd.read_sql()`) is used only to execute the query and pass results to Matplotlib for visualization. This keeps the analytical logic readable, portable, and database-agnostic.

**payment_method on payments**
Added to explain payment timing patterns in the data: Emily Rodriguez, Priya Patel, and Olivia Tremblay use auto-debit — which is why they always pay on exactly the due date. Tyler Brooks uses e-transfer manually — which is why he's frequently late. The data tells a coherent story.
