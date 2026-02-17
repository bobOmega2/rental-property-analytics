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

## February 17, 2026 - SQLTools Setup, Schema Deployed, Data Strategy

### What I Did Today
- Reinstalled Python packages on new computer (`psycopg2-binary`, `python-dotenv`, `pandas`, `matplotlib`)
- Configured SQLTools extension in VS Code and connected to Supabase
- Deployed schema to Supabase — all 6 tables confirmed created in the `public` schema
- Decided on a dual-environment data strategy (mock data for portfolio, real data locally)

### SQLTools Configuration

The key issues I ran into and solved:

**1. IPv4 vs IPv6 — why Direct Connection didn't work**
Supabase's Direct Connection (`db.[project].supabase.co:5432`) is IPv6 only on the free tier. My laptop is on an IPv4 network (most home/university networks are). IPv4 and IPv6 are two different addressing systems — IPv4 is the old standard (addresses like `192.168.1.1`), IPv6 is the newer one (long colon-separated strings). Supabase doesn't assign free-tier projects an IPv4 address for direct connections because IPv4 addresses are now scarce and expensive.

**Solution: Session Pooler**
The Session Pooler (`aws-1-us-east-2.pooler.supabase.com:5432`) has an IPv4 address. I connect to it over IPv4, and it connects to the database internally over IPv6. I never touch IPv6 directly. Supabase explicitly recommends this for IPv4 networks.

**Session vs Transaction Pooler:**
- Session Pooler: you hold one connection for your entire session — behaves like a direct connection, supports all SQL features. Right choice for interactive tools like SQLTools.
- Transaction Pooler: connection is only held during a single transaction, then released. Designed for high-traffic web apps with hundreds of concurrent users. Has SQL limitations (no session-level settings, no temp tables that persist). Not needed for a single-user analytics project.

**2. SSL — rejectUnauthorized**
Supabase requires SSL (encrypted connections). SQLTools defaults to `rejectUnauthorized: true`, which means it only accepts certificates signed by a trusted certificate authority (CA). Supabase uses a self-signed certificate, which isn't on that list, so the connection was rejected with "self signed certificate in certificate chain."

**Solution:** Unchecked `rejectUnauthorized` in SQLTools SSL options. The connection is still encrypted — I'm just skipping certificate authority verification. Safe for a known, trusted service like Supabase on a private network.

**3. Verifying the connection worked**
```sql
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
```
`information_schema` is PostgreSQL's built-in metadata directory — it stores data *about* the database (table names, column types, constraints, etc.). Filtering by `table_schema = 'public'` shows only my tables, not Supabase's internal schemas (`auth`, `storage`, `realtime`, etc.).

### Data Strategy Decision

**The problem:** I want real numbers on my resume but don't want to put sensitive tenant data on GitHub.

**Decision: Two environments**

| Environment | Data | Purpose |
|---|---|---|
| Supabase (cloud) | Realistic mock data | Public portfolio on GitHub |
| Local PostgreSQL (future) | Real property data | Actual analysis, private |

**Why local for real data:**
Real tenant data (names, payment history, contact info) is sensitive personal/financial information. Keeping it off the cloud entirely is the responsible choice — no third-party breach risk, no internet exposure. The `.env` file already makes this easy to swap: just change `DATABASE_URL` to point to `localhost` instead of Supabase.

**Why mock data is fine for the portfolio:**
The resume bullet is about what I built and what I found, not the raw numbers. Interviewers care about schema design, query complexity, and insight quality — not whether the data was real. The mock data will be designed to have realistic patterns (late payments, vacancies, expense spikes) so the analysis is meaningful.

**Resume framing:**
- On the resume: describe what the system does and what insights it surfaces
- In the GitHub README: one line noting it uses representative mock data
- In interviews: "modeled after a real property, real data kept locally for privacy reasons" — this actually demonstrates data privacy awareness, which is a plus

**Environment-agnostic design:**
The fact that the same schema, queries, and notebook work against both environments just by changing `DATABASE_URL` is itself worth mentioning in an interview — it shows I designed for portability from the start.

### Technical Learnings
- **IPv4 vs IPv6**: Two different internet addressing systems. IPv4 is running out of addresses; IPv6 is the replacement. Most consumer networks are still IPv4.
- **Connection pooler as IPv4 bridge**: Pooler sits on a server with both IPv4 and IPv6. You connect to it over IPv4; it connects to the DB internally over IPv6.
- **SSL/TLS**: Encrypts data in transit. `rejectUnauthorized` controls whether the server's certificate must be signed by a known certificate authority.
- **DDL commands return no rows**: `CREATE TABLE`, `DROP TABLE` etc. modify structure — empty result in SQLTools means success, not failure.
- **`information_schema`**: PostgreSQL's built-in metadata layer. Query it to inspect your own database structure programmatically.

### Seed Data
Generated and inserted realistic mock data:
- 1 property, 8 units (rooms), 10 tenants (8 original + 2 replacements for turnover)
- 205 payments across 26 months (Jan 2024 – Feb 2026)
- Intentional patterns built in: Tyler Brooks (9 late payments), Sarah Chen (5 late), Michael Okafor (1 missed + early termination), 3-month vacancy on R5
- Expenses: property tax (quarterly), insurance (annual), management fees (monthly), utilities, unit-specific repairs

### Constraints Added
After seeding, added additional constraints via `ALTER TABLE`:
```sql
ALTER TABLE tenants ADD CONSTRAINT uq_tenant_email UNIQUE (email);
ALTER TABLE tenants ADD CONSTRAINT uq_tenant_phone UNIQUE (phone);
ALTER TABLE properties ADD CONSTRAINT uq_property_address UNIQUE (address);
ALTER TABLE leases ADD CONSTRAINT chk_deposit_positive CHECK (security_deposit IS NULL OR security_deposit >= 0);
ALTER TABLE units ADD CONSTRAINT chk_sqft_positive CHECK (square_feet IS NULL OR square_feet > 0);
ALTER TABLE properties ADD CONSTRAINT chk_postal_code_format CHECK (postal_code ~ '^[A-Z][0-9][A-Z] [0-9][A-Z][0-9]$');
```

Tested each constraint by running intentional bad inserts — all correctly threw errors. The important distinction: constraints that enforce *business rules* (no two tenants share an email/phone) are more meaningful than constraints purely for deduplication. Both goals are served here.

**Note on re-seeding:** running `seed_data.sql` twice would duplicate all rows. Safe reset pattern:
```sql
TRUNCATE properties, units, tenants, leases, payments, expenses RESTART IDENTITY CASCADE;
```
`CASCADE` is required because child tables (payments, leases) have foreign keys pointing to parent tables — PostgreSQL won't truncate a parent while children still reference it.

### Next Steps
- [ ] Begin writing analysis queries (cash flow, payment delinquency, expense breakdown, vacancy)
- [ ] Update schema.sql to include all new constraints so file stays source of truth
- [ ] Build out Jupyter notebook with visualizations
- [ ] (Later) Set up local PostgreSQL for real data

---
