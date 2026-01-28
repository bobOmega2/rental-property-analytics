-- ============================================
-- Rental Property Analytics - Database Schema
-- ============================================
-- Normalized PostgreSQL schema for analyzing
-- rental property financial and operational data.
-- ============================================

-- Drop tables if they exist (in reverse dependency order)
DROP TABLE IF EXISTS expenses;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS leases;
DROP TABLE IF EXISTS tenants;
DROP TABLE IF EXISTS units;
DROP TABLE IF EXISTS properties;

-- 1. Properties
-- Top-level table. Each row is a rental property (building/house).
CREATE TABLE properties (
    property_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    address VARCHAR(255) NOT NULL,
    city VARCHAR(100) NOT NULL,
    province CHAR(2) NOT NULL CHECK (province IN ('ON', 'BC', 'AB', 'QC', 'MB', 'SK', 'NB', 'NS', 'PE', 'NL', 'YT', 'NT', 'NU')),
    postal_code VARCHAR(10) NOT NULL
);

-- 2. Units
-- Individual rental units within a property (rooms, apartments, studios, etc.).
-- For single-unit properties, use suite number or "Main" as the label.
CREATE TABLE units (
    unit_id SERIAL PRIMARY KEY,
    property_id INT NOT NULL REFERENCES properties(property_id),
    unit_label VARCHAR(10) NOT NULL,
    unit_type VARCHAR(20) NOT NULL CHECK (unit_type IN ('room', 'apartment', 'studio', 'other')),
    square_feet INT,
    monthly_rent NUMERIC(10,2) NOT NULL CHECK (monthly_rent > 0),
    UNIQUE (property_id, unit_label)
);

-- 3. Tenants
-- Standalone table for people renting units.
CREATE TABLE tenants (
    tenant_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100),
    phone VARCHAR(20)
);

-- 4. Leases
-- Connects a tenant to a unit for a specific time period.
-- monthly_rent is stored here (not as FK to units) because
-- rent can change between leases while preserving history.
CREATE TABLE leases (
    lease_id SERIAL PRIMARY KEY,
    unit_id INT NOT NULL REFERENCES units(unit_id),
    tenant_id INT NOT NULL REFERENCES tenants(tenant_id),
    start_date DATE NOT NULL,
    end_date DATE CHECK (end_date > start_date),
    monthly_rent NUMERIC(10,2) NOT NULL CHECK (monthly_rent > 0),
    security_deposit NUMERIC(10,2),
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'terminated'))
);

-- 5. Payments
-- Rent payments linked to leases.
-- payment_date is TIMESTAMP (exact time), due_date is DATE (just the day).
CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY,
    lease_id INT NOT NULL REFERENCES leases(lease_id),
    amount NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    payment_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    due_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'on_time' CHECK (status IN ('on_time', 'late', 'missed'))
);

-- 6. Expenses
-- Operating costs for the property or specific units.
-- unit_id is nullable: NULL = property-wide expense (tax, insurance),
-- non-NULL = unit-specific expense (repairs, appliance replacement).
CREATE TABLE expenses (
    expense_id SERIAL PRIMARY KEY,
    property_id INT NOT NULL REFERENCES properties(property_id),
    unit_id INT REFERENCES units(unit_id),
    category VARCHAR(30) NOT NULL CHECK (category IN ('maintenance', 'utilities', 'insurance', 'property_tax', 'management', 'other')),
    description TEXT,
    amount NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    expense_date DATE NOT NULL
);
