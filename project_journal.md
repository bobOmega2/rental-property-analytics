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
