# Rental Property Analytics

PostgreSQL analytics system for tracking rental property financials. Built around a real Canadian rental property — cash flow, vacancy, expenses, and tenant payment patterns.

> **Note:** The data in this repo is synthetic demo data, not the real property's numbers. A private version with real (anonymized) data exists and can be shared on request.

## What it does

| Analysis | Question answered |
|---|---|
| Monthly cash flow | How much came in vs went out each month? |
| Payment delinquency | Which tenants pay late, and are the fees being collected? |
| Vacancy analysis | How long did units sit empty and what did it cost? |
| Expense breakdown | Where is the money going, and what's deductible now vs depreciated later? |
| Rent roll | Who is in each unit right now and what are they paying? |
| Year-over-year | How did 2024 compare to 2025? |

Queries are in `queries.sql`. Visualizations are in `rental_analytics.ipynb` using pandas and Matplotlib.

## Schema

7-table normalized PostgreSQL schema: properties → units → leases → payments, with tenants linked through leases and expenses tracked at both property and unit level.

Key accounting features:
- **OpEx vs CapEx** — matches CRA T776 line items so expense queries produce tax-correct numbers, not just total spending
- **Mortgage tracking** — separated from operating expenses since only the interest portion is deductible
- **CCA asset tracking** — capital purchases link to an assets table with CCA class and depreciation rate (Class 1 at 4% for the building, Class 8 at 20% for appliances)
- **Security deposit lifecycle** — tracked as a liability until returned or applied, with partial withholding and reason fields
- **Late fee accounting** — fees charged vs collected tracked separately so waiver patterns show up in the data

## Stack

- **Database**: PostgreSQL on Supabase
- **Analysis**: SQL + Jupyter notebook
- **Python**: psycopg2, pandas, Matplotlib

## Running it locally

1. Clone the repo
2. Add a `.env` file:
   ```
   DATABASE_URL=postgresql://user:password@host:port/dbname
   ```
3. Run `schema.sql` to create the tables
4. Run `seed_data.sql` to load the demo data
5. Open `rental_analytics.ipynb` and run all cells

## Design decisions

See [`design_decisions.md`](design_decisions.md) for reasoning behind key choices — why `monthly_rent` lives on leases rather than units, why this uses cash basis instead of double-entry bookkeeping, and why expenses have an `expense_class` column.
