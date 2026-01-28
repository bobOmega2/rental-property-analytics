# Rental Property Analytics - Project Journal

Documenting my thought process, decisions, and learnings throughout this project.

---

## January 26, 2026 - Project Setup

### What I Did Today
- Set up Supabase PostgreSQL database (cloud-hosted)
- Configured environment variables (`.env` with `DATABASE_URL`)
- Created GitHub repository and pushed initial code
- Installed Python packages: `psycopg2-binary`, `python-dotenv`, `pandas`, `matplotlib`
- Successfully tested database connection from Jupyter notebook
- Started setting up SQLTools extension in VS Code for direct SQL work

### Key Decisions Made

**1. Supabase over local PostgreSQL**
- Chose cloud-hosted database for easier setup and accessibility
- Free tier sufficient for this project's scale (6-8 tenants, 12+ months data)

**2. Direct connection approach**
- Using `psycopg2` for direct SQL execution rather than an ORM
- Aligns with project goal: demonstrate SQL skills, not abstract them away

**3. SQL-first workflow**
- Python/Pandas only for visualization and light post-processing
- All analysis logic written in raw SQL queries
- SQLTools extension for writing SQL directly in VS Code

**4. Python 3.14.2 (standalone) over Anaconda**
- Cleaner setup, packages installed via pip
- Avoided confusion with multiple Python environments

### Technical Learnings
- **PATH**: A list of folders Windows searches when running commands (not a single folder)
- **Kernel**: The "engine" that executes code in Jupyter notebooks
- **Cursor**: The object that sends SQL queries and retrieves results (like a waiter between you and the database)
- **Connection pooling vs direct connection**: Pooling shares connections for high-traffic apps; direct is simpler for single-user analytics

### Next Steps
- [ ] Finish SQLTools configuration
- [ ] Design and create database schema (tables for tenants, units, payments, expenses, leases)
- [ ] Insert sample/mock data
- [ ] Begin writing analysis queries

---

## January 28, 2026 - Schema Design

### What I Did Today
- Designed and wrote the full database schema (6 tables)
- Focused on making everything standardized and analysis-friendly before writing any queries

### Schema Overview

I decided on 6 tables: `properties`, `units`, `tenants`, `leases`, `payments`, and `expenses`. The idea is that `properties` sits at the top, and everything else chains down from it through foreign keys.

```
properties → units → leases → payments
                  ↘ expenses
tenants → leases
```

### Why I Designed It This Way

**Not everything links directly to `property_id`.** My first instinct was to connect every table straight to the property, like objects in Python. But SQL doesn't work that way — each table links to its immediate parent, and you follow the chain with JOINs when you need the full picture. This avoids duplicate data and keeps things clean.

**`monthly_rent` lives on both `units` and `leases`.** The unit table stores the current/default rent, but the lease stores what was actually agreed. If a tenant negotiated a lower rate, or rent went up between leases, the historical data stays accurate. It's not a foreign key — it's a separate value.

**Expenses can be property-wide or unit-specific.** I made `unit_id` nullable on the expenses table. If it's NULL, the expense applies to the whole property (like property tax or insurance). If it has a value, it's tied to a specific unit (like a plumbing repair). This lets me slice expenses either way in my analysis.

**Payments track on-time vs late.** I added a `due_date` and `status` field ('on_time', 'late', 'missed') so I can analyze tenant payment behavior — not just that they paid, but whether they paid on time.

### Standardization Decisions

I wanted to make sure any field I'd use for `GROUP BY` or `WHERE` filters has consistent values:

- **Province**: `CHAR(2)` with CHECK constraint — only valid 2-letter Canadian codes (ON, BC, AB, etc.). No "Ontario" vs "ontario" vs "ON" inconsistencies.
- **Expense categories**: Fixed list via CHECK — maintenance, utilities, insurance, property_tax, management, other.
- **Lease status**: CHECK — active, expired, terminated.
- **Payment status**: CHECK — on_time, late, missed.
- **Amounts**: `NUMERIC(10,2)` with CHECK > 0 — always positive, always 2 decimal places.

I skipped adding a `country` field for now. The project is about one Canadian property — I can always `ALTER TABLE ADD COLUMN` later if I expand. No point designing for hypothetical requirements.

### Schema First, Not Data First

I chose to design the schema before looking at any data. Since I know the domain (my family's rental property) and I know what questions I want to answer (cash flow, turnover, expenses), it made sense to model the structure first and then generate data to fill it. The opposite approach (data first) is better when you receive a messy dataset and need to figure out what to do with it.

### Next Steps
- [ ] Set up SQLTools in VS Code
- [ ] Run schema SQL in Supabase to create tables
- [ ] Generate and insert mock data
- [ ] Begin writing analysis queries

---
