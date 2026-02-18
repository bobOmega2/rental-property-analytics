-- ============================================
-- Rental Property Analytics - Database Schema
-- ============================================
-- Normalized PostgreSQL schema for analyzing
-- rental property financial and operational data.
-- Canadian context: amounts in CAD, CCA classes
-- per CRA Guide T4036 (Rental Income).
--
-- 7 tables:
--   properties → units → leases → payments
--                      ↘ expenses → assets
--                 tenants → leases
--
-- All constraints are inline (no ALTER TABLE patches).
-- ============================================


-- Drop tables if they exist (reverse dependency order)
-- assets must go first: references expenses, units, properties
DROP TABLE IF EXISTS assets;
DROP TABLE IF EXISTS expenses;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS leases;
DROP TABLE IF EXISTS tenants;
DROP TABLE IF EXISTS units;
DROP TABLE IF EXISTS properties;


-- ============================================
-- 1. Properties
-- ============================================
-- Top-level table. Each row is a rental property.
CREATE TABLE properties (
    property_id SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    address     VARCHAR(255) NOT NULL UNIQUE,  -- no duplicate properties
    city        VARCHAR(100) NOT NULL,
    province    CHAR(2) NOT NULL CHECK (province IN ('ON', 'BC', 'AB', 'QC', 'MB', 'SK', 'NB', 'NS', 'PE', 'NL', 'YT', 'NT', 'NU')),
    postal_code VARCHAR(10)  NOT NULL CHECK (postal_code ~ '^[A-Z][0-9][A-Z] [0-9][A-Z][0-9]$')
    -- ~ is PostgreSQL's regex match operator. ^ = start, $ = end.
    -- Pattern enforces Canadian postal code format: A1A 1A1
);


-- ============================================
-- 2. Units
-- ============================================
-- Individual rental units within a property (rooms, apartments, etc.).
CREATE TABLE units (
    unit_id      SERIAL PRIMARY KEY,
    property_id  INT           NOT NULL REFERENCES properties(property_id),
    unit_label   VARCHAR(10)   NOT NULL,
    unit_type    VARCHAR(20)   NOT NULL CHECK (unit_type IN ('room', 'apartment', 'studio', 'other')),
    square_feet  INT           CHECK (square_feet IS NULL OR square_feet > 0),
    monthly_rent NUMERIC(10,2) NOT NULL CHECK (monthly_rent > 0),
    UNIQUE (property_id, unit_label)  -- no duplicate room labels within the same property
);


-- ============================================
-- 3. Tenants
-- ============================================
-- People who rent units. Standalone table linked to units via leases.
CREATE TABLE tenants (
    tenant_id  SERIAL PRIMARY KEY,
    first_name VARCHAR(50)  NOT NULL,
    last_name  VARCHAR(50)  NOT NULL,
    email      VARCHAR(100) UNIQUE,  -- no two tenants share an email
    phone      VARCHAR(20)  UNIQUE   -- no two tenants share a phone number
);


-- ============================================
-- 4. Leases
-- ============================================
-- Connects a tenant to a unit for a specific period.
-- monthly_rent stored here (not FK to units) because rent can change
-- between leases while preserving historical accuracy.
--
-- Security deposit lifecycle:
--   In accounting, a deposit collected is a LIABILITY — you owe it back.
--   These columns track what happened to it at lease end:
--   deposit_returned_amount : actual amount refunded to tenant
--   deposit_deductions      : amount withheld (e.g. unpaid rent, damages)
--   deposit_deduction_reason: explanation for any withholding (audit trail)
--   NULL values = lease still active (deposit not yet resolved)
CREATE TABLE leases (
    lease_id                SERIAL PRIMARY KEY,
    unit_id                 INT           NOT NULL REFERENCES units(unit_id),
    tenant_id               INT           NOT NULL REFERENCES tenants(tenant_id),
    start_date              DATE          NOT NULL,
    end_date                DATE          CHECK (end_date > start_date),
    monthly_rent            NUMERIC(10,2) NOT NULL CHECK (monthly_rent > 0),
    security_deposit        NUMERIC(10,2) CHECK (security_deposit IS NULL OR security_deposit >= 0),
    status                  VARCHAR(20)   NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'terminated')),
    -- Deposit lifecycle (NULL until lease ends)
    deposit_returned_date   DATE,
    deposit_returned_amount NUMERIC(10,2) CHECK (deposit_returned_amount >= 0),
    deposit_deductions      NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (deposit_deductions >= 0),
    deposit_deduction_reason TEXT
);


-- ============================================
-- 5. Payments
-- ============================================
-- Rent payments linked to leases.
-- payment_date is TIMESTAMP (exact time received).
-- due_date is DATE (the 1st of each month).
--
-- payment_method: how rent arrived — useful audit trail.
--   Auto-debit tenants tend to pay on exactly the due date.
--   E-transfer/cheque tenants may vary by days.
--
-- late_fee_charged  : fee assessed for a late payment ($50 standard here).
--   NULL = no fee charged (on_time or missed payments don't get a fee).
-- late_fee_collected: of the fee charged, how much was actually received.
--   0 = fee was charged but waived or unpaid.
--   NULL = no fee was charged at all.
CREATE TABLE payments (
    payment_id         SERIAL PRIMARY KEY,
    lease_id           INT           NOT NULL REFERENCES leases(lease_id),
    amount             NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    payment_date       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    due_date           DATE          NOT NULL,
    status             VARCHAR(20)   NOT NULL DEFAULT 'on_time' CHECK (status IN ('on_time', 'late', 'missed')),
    payment_method     VARCHAR(20)   NOT NULL CHECK (payment_method IN ('e-transfer', 'cheque', 'cash', 'auto-debit')),
    late_fee_charged   NUMERIC(10,2) CHECK (late_fee_charged >= 0),
    late_fee_collected NUMERIC(10,2) CHECK (late_fee_collected >= 0)
);


-- ============================================
-- 6. Expenses
-- ============================================
-- Operating costs for the property or specific units.
-- unit_id is nullable:
--   NULL = property-wide expense (tax, insurance, management)
--   non-NULL = unit-specific expense (plumbing repair in R1)
--
-- expense_class: the key accounting distinction for CRA Form T776:
--   'opex' (operating expense): fully deducted in the tax year incurred.
--     Examples: repairs, management fees, insurance, property tax, utilities.
--   'capex' (capital expenditure): purchase creates or significantly improves
--     an asset. NOT deducted immediately — depreciated over years via CCA.
--     Examples: new appliance, furnace replacement, structural improvements.
--
-- Without this distinction, the P&L overstates expenses in any year with
-- a major capital purchase, and taxable income is incorrectly calculated.
CREATE TABLE expenses (
    expense_id    SERIAL PRIMARY KEY,
    property_id   INT           NOT NULL REFERENCES properties(property_id),
    unit_id       INT           REFERENCES units(unit_id),
    category      VARCHAR(30)   NOT NULL CHECK (category IN ('maintenance', 'utilities', 'insurance', 'property_tax', 'management', 'other')),
    expense_class VARCHAR(10)   NOT NULL CHECK (expense_class IN ('opex', 'capex')),
    description   TEXT,
    amount        NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    expense_date  DATE          NOT NULL
);


-- ============================================
-- 7. Assets
-- ============================================
-- NOTE: Refer to this for taxes: 
-- https://www.canada.ca/en/revenue-agency/services/tax/businesses/topics/
-- sole-proprietorships-partnerships/report-business-income-expenses/
-- claiming-capital-cost-allowance/classes-depreciable-property.html

-- Tracks capital assets and their CCA (Capital Cost Allowance) depreciation.
-- CCA is Canada's tax system for deducting depreciation on capital assets
-- (CRA Guide T4036, Rental Income). Assets are assigned to CCA classes
-- that define the depreciation method and annual rate.
--
-- Key CCA classes for rental property:
--   Class 1  (4%  declining balance) : the building itself (most significant)
--   Class 8  (20% declining balance) : furniture, appliances, equipment
--   Class 10 (30% declining balance) : vehicles used for property management
--   Class 12 (100% in year of purchase): small tools and software under $500
--
-- Declining balance means: each year you depreciate the remaining book value,
-- not the original cost. So a $1,000 Class 8 asset depreciates:
--   Year 1: $100 (half-year rule: 20% × $1,000 × 50%)
--   Year 2: $180 (20% × $900 remaining UCC)
--   Year 3: $144 (20% × $720 remaining UCC), etc.
-- UCC = Undepreciated Capital Cost (book value for tax purposes)
--
-- expense_id: links to the CapEx expense that purchased this asset.
--   NULL = asset acquired before this system's tracking period.
-- disposal_date / disposal_amount: when and how much the asset was sold for.
--   Proceeds affect the UCC pool and may trigger recapture or terminal loss.
CREATE TABLE assets (
    asset_id         SERIAL PRIMARY KEY,
    property_id      INT           NOT NULL REFERENCES properties(property_id),
    unit_id          INT           REFERENCES units(unit_id),
    expense_id       INT           REFERENCES expenses(expense_id),
    description      VARCHAR(200)  NOT NULL,
    cca_class        VARCHAR(10)   NOT NULL CHECK (cca_class IN ('class_1', 'class_8', 'class_10', 'class_12')),
    cca_rate         NUMERIC(5,4)  NOT NULL CHECK (cca_rate > 0),
    acquisition_date DATE          NOT NULL,
    acquisition_cost NUMERIC(10,2) NOT NULL CHECK (acquisition_cost > 0),
    salvage_value    NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (salvage_value >= 0),
    disposal_date    DATE,
    disposal_amount  NUMERIC(10,2) CHECK (disposal_amount >= 0)
);
