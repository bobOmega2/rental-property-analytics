# Rental Property Analytics

A PostgreSQL analytics system for tracking rental property financials — cash flow, tenant delinquency, vacancy, and expenses. Built to demonstrate SQL skills alongside Canadian real estate accounting concepts (CRA T776, CCA depreciation).

## What it does

Six analysis queries covering the core questions a landlord or property manager would ask:

| Query | Question answered |
|---|---|
| Monthly cash flow | How much came in vs went out each month? |
| Payment delinquency | Which tenants pay late, and are we collecting the fees? |
| Vacancy analysis | How long did units sit empty, and what did it cost? |
| Expense breakdown | Where is the money going, and what's tax-deductible now vs later? |
| Rent roll | Who is in each unit right now and what are they paying? |
| Year-over-year | How did 2024 compare to 2025? |

Results are visualized in a Jupyter notebook using pandas and Matplotlib.

## Schema

7-table normalized PostgreSQL schema — properties → units → leases → payments, with tenants linked through leases and expenses tracked at both property and unit level.

Key accounting features built into the schema:
- **OpEx vs CapEx** on expenses — matches CRA T776 line items, so queries produce tax-correct numbers rather than lumping all spending together
- **CCA asset tracking** — capital purchases link to an assets table with CCA class and rate (Class 1 for the building at 4%, Class 8 for appliances at 20%)
- **Security deposit lifecycle** — deposits are tracked as a liability until returned or applied, including partial withholdings with a reason field
- **Late fee accounting** — separate columns for fees charged vs collected, so fee waiver patterns are visible in the data

## Tech stack

- **Database**: PostgreSQL (hosted on Supabase)
- **Analysis**: SQL (`queries.sql`) + Jupyter notebook (`rental_analytics.ipynb`)
- **Python**: psycopg2, pandas, Matplotlib
- **Data**: Mock data modeled on Canadian rental market rates and CRA T776 requirements

## Running it locally

1. Clone the repo
2. Create a `.env` file with your database connection:
   ```
   DATABASE_URL=postgresql://user:password@host:port/dbname
   ```
3. Run `schema.sql` to create the tables
4. Run `seed_data.sql` to load the mock data
5. Open `rental_analytics.ipynb` and run all cells

The `.env` file is gitignored — swap in a different `DATABASE_URL` to point at any PostgreSQL database without touching the code.

## Design decisions

See [`design_decisions.md`](design_decisions.md) for the reasoning behind key choices — why `monthly_rent` lives on leases rather than units, why this uses cash basis instead of double-entry bookkeeping, and why expenses have an `expense_class` column.
