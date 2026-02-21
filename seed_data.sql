-- ============================================
-- Rental Property Analytics - Seed Data
-- ============================================
-- Realistic mock data modeled after a Canadian rental property.
-- Property : 8-room house in Hamilton, ON
-- Tenants  : 8 original + 2 replacements (2 units had turnover)
-- Period   : January 2024 – February 2026 (26 months)
-- Currency : All monetary values in CAD (implied; single-country system)
--
-- Safe reset before re-running:
--   TRUNCATE assets, expenses, payments, leases, tenants, units, properties
--   RESTART IDENTITY CASCADE;
--   (assets added to front since it references expenses)
-- ============================================


-- ============================================
-- 1. PROPERTY
-- ============================================
INSERT INTO properties (name, address, city, province, postal_code) VALUES
('Maple Street House', '142 Maple Street', 'Hamilton', 'ON', 'L8P 2T4');
-- property_id = 1


-- ============================================
-- 2. UNITS (8 rooms)
-- ============================================
INSERT INTO units (property_id, unit_label, unit_type, square_feet, monthly_rent) VALUES
(1, 'R1', 'room', 180, 750.00),
(1, 'R2', 'room', 195, 800.00),
(1, 'R3', 'room', 210, 850.00),
(1, 'R4', 'room', 170, 700.00),
(1, 'R5', 'room', 185, 750.00),
(1, 'R6', 'room', 220, 900.00),
(1, 'R7', 'room', 180, 750.00),
(1, 'R8', 'room', 160, 650.00);
-- unit_ids = 1 (R1) through 8 (R8)


-- ============================================
-- 3. TENANTS
-- 8 original + 2 replacements for turnover units (R3 and R5)
-- ============================================
INSERT INTO tenants (first_name, last_name, email, phone) VALUES
('James',   'Wilson',    'james.wilson@email.com',    '905-555-0101'),  -- 1: R1, active, always on time
('Sarah',   'Chen',      'sarah.chen@email.com',      '905-555-0102'),  -- 2: R2, active, 5 late payments
('Michael', 'Okafor',    'michael.okafor@email.com',  '905-555-0103'),  -- 3: R3, terminated Oct 2024, 1 missed payment
('Emily',   'Rodriguez', 'emily.rodriguez@email.com', '905-555-0104'),  -- 4: R4, active, always on time (auto-debit)
('David',   'Kim',       'david.kim@email.com',       '905-555-0105'),  -- 5: R5, lease expired May 2024
('Priya',   'Patel',     'priya.patel@email.com',     '905-555-0106'),  -- 6: R6, active, always on time (auto-debit)
('Tyler',   'Brooks',    'tyler.brooks@email.com',    '905-555-0107'),  -- 7: R7, active, 9 late payments
('Aisha',   'Mahmoud',   'aisha.mahmoud@email.com',   '905-555-0108'),  -- 8: R8, active, always on time
('Lucas',   'Nguyen',    'lucas.nguyen@email.com',    '905-555-0109'),  -- 9: R3 replacement (Nov 2024)
('Olivia',  'Tremblay',  'olivia.tremblay@email.com', '905-555-0110'); -- 10: R5 replacement (Sep 2024, auto-debit)
-- tenant_ids = 1–10


-- ============================================
-- 4. LEASES
-- ============================================
-- R3 had turnover: Michael Okafor terminated Oct 2024, Lucas Nguyen moved in Nov 2024 (no vacancy gap).
-- R5 had turnover: David Kim expired May 2024, Olivia Tremblay moved in Sep 2024 (3-month vacancy Jun–Aug).
--
-- Deposit lifecycle columns:
--   deposit_returned_date / deposit_returned_amount / deposit_deductions / deposit_deduction_reason
--   NULL for active leases (deposit not yet resolved).
--
-- Michael Okafor (lease 3, terminated): full deposit withheld for his missed Aug 2024 rent.
--   Deposit collected: $850. Deductions: $850 (unpaid rent). Returned: $0.
-- David Kim (lease 5, expired cleanly): full deposit returned.
--   Deposit collected: $750. Deductions: $0. Returned: $750.
INSERT INTO leases (unit_id, tenant_id, start_date, end_date, monthly_rent, security_deposit, status,
                    deposit_returned_date, deposit_returned_amount, deposit_deductions, deposit_deduction_reason) VALUES
(1, 1,  '2024-01-01', NULL,         750.00, 750.00, 'active',     NULL,         NULL,   0.00, NULL),
(2, 2,  '2024-01-01', NULL,         800.00, 800.00, 'active',     NULL,         NULL,   0.00, NULL),
(3, 3,  '2024-01-01', '2024-10-31', 850.00, 850.00, 'terminated', '2024-11-15', 0.00,  850.00, 'Applied to unpaid August 2024 rent ($850.00)'),
(4, 4,  '2024-01-01', NULL,         700.00, 700.00, 'active',     NULL,         NULL,   0.00, NULL),
(5, 5,  '2024-01-01', '2024-05-31', 750.00, 750.00, 'expired',    '2024-06-15', 750.00, 0.00, NULL),
(6, 6,  '2024-01-01', NULL,         900.00, 900.00, 'active',     NULL,         NULL,   0.00, NULL),
(7, 7,  '2024-01-01', NULL,         750.00, 750.00, 'active',     NULL,         NULL,   0.00, NULL),
(8, 8,  '2024-01-01', NULL,         650.00, 650.00, 'active',     NULL,         NULL,   0.00, NULL),
(3, 9,  '2024-11-01', NULL,         875.00, 875.00, 'active',     NULL,         NULL,   0.00, NULL),
(5, 10, '2024-09-01', NULL,         775.00, 775.00, 'active',     NULL,         NULL,   0.00, NULL);
-- lease_ids = 1–10


-- ============================================
-- 5. PAYMENTS (205 rows)
-- ============================================
-- on_time: paid 1–2 days after the 1st (same day for auto-debit)
-- late:    paid 7–12 days after the 1st
-- missed:  logged 2 days after due date; amount = what was owed
--
-- Payment methods (explains the patterns):
--   L1 James Wilson      e-transfer
--   L2 Sarah Chen        e-transfer   — 5 late payments
--   L3 Michael Okafor    cheque       — 1 missed payment
--   L4 Emily Rodriguez   auto-debit   — always on time
--   L5 David Kim         e-transfer   — 5 months then gone
--   L6 Priya Patel       auto-debit   — always on time
--   L7 Tyler Brooks      e-transfer   — 9 late payments
--   L8 Aisha Mahmoud     e-transfer   — always on time
--   L9 Lucas Nguyen      e-transfer   — always on time
--   L10 Olivia Tremblay  auto-debit   — always on time
--
-- Late fee policy: $50 charged per late payment.
--   Sarah Chen: all 5 collected.
--   Tyler Brooks: first 5 collected, last 4 waived.
--   Missed payments: no fee (handled via deposit instead).

INSERT INTO payments (lease_id, amount, payment_date, due_date, status, payment_method, late_fee_charged, late_fee_collected) VALUES

-- ----------------------------------------
-- Lease 1: James Wilson | R1 | $750 | Jan 2024–Feb 2026 | always on time | e-transfer
-- ----------------------------------------
(1, 750.00, '2024-01-02 09:15:00', '2024-01-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2024-02-02 09:15:00', '2024-02-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2024-03-02 09:15:00', '2024-03-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2024-04-02 09:15:00', '2024-04-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2024-05-02 09:15:00', '2024-05-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2024-06-02 09:15:00', '2024-06-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2024-07-02 09:15:00', '2024-07-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2024-08-02 09:15:00', '2024-08-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2024-09-02 09:15:00', '2024-09-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2024-10-02 09:15:00', '2024-10-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2024-11-02 09:15:00', '2024-11-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2024-12-02 09:15:00', '2024-12-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2025-01-02 09:15:00', '2025-01-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2025-02-02 09:15:00', '2025-02-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2025-03-02 09:15:00', '2025-03-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2025-04-02 09:15:00', '2025-04-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2025-05-02 09:15:00', '2025-05-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2025-06-02 09:15:00', '2025-06-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2025-07-02 09:15:00', '2025-07-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2025-08-02 09:15:00', '2025-08-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2025-09-02 09:15:00', '2025-09-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2025-10-02 09:15:00', '2025-10-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2025-11-02 09:15:00', '2025-11-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2025-12-02 09:15:00', '2025-12-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2026-01-02 09:15:00', '2026-01-01', 'on_time', 'e-transfer', NULL, NULL),
(1, 750.00, '2026-02-02 09:15:00', '2026-02-01', 'on_time', 'e-transfer', NULL, NULL),

-- ----------------------------------------
-- Lease 2: Sarah Chen | R2 | $800 | Jan 2024–Feb 2026
-- Late: Mar/Jul/Nov 2024, Apr/Sep 2025 — all fees collected
-- ----------------------------------------
(2, 800.00, '2024-01-02 10:30:00', '2024-01-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2024-02-02 11:00:00', '2024-02-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2024-03-09 14:00:00', '2024-03-01', 'late',    'e-transfer', 50.00, 50.00),
(2, 800.00, '2024-04-02 10:00:00', '2024-04-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2024-05-02 09:30:00', '2024-05-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2024-06-03 10:00:00', '2024-06-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2024-07-11 15:00:00', '2024-07-01', 'late',    'e-transfer', 50.00, 50.00),
(2, 800.00, '2024-08-02 10:00:00', '2024-08-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2024-09-02 09:00:00', '2024-09-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2024-10-02 11:00:00', '2024-10-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2024-11-08 16:00:00', '2024-11-01', 'late',    'e-transfer', 50.00, 50.00),
(2, 800.00, '2024-12-02 10:00:00', '2024-12-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2025-01-02 09:30:00', '2025-01-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2025-02-03 10:00:00', '2025-02-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2025-03-02 11:00:00', '2025-03-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2025-04-12 14:30:00', '2025-04-01', 'late',    'e-transfer', 50.00, 50.00),
(2, 800.00, '2025-05-02 09:00:00', '2025-05-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2025-06-02 10:00:00', '2025-06-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2025-07-02 09:30:00', '2025-07-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2025-08-03 11:00:00', '2025-08-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2025-09-10 15:00:00', '2025-09-01', 'late',    'e-transfer', 50.00, 50.00),
(2, 800.00, '2025-10-02 09:00:00', '2025-10-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2025-11-02 10:00:00', '2025-11-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2025-12-02 09:30:00', '2025-12-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2026-01-02 10:00:00', '2026-01-01', 'on_time', 'e-transfer', NULL,  NULL),
(2, 800.00, '2026-02-02 09:00:00', '2026-02-01', 'on_time', 'e-transfer', NULL,  NULL),

-- ----------------------------------------
-- Lease 3: Michael Okafor | R3 | $850 | Jan–Oct 2024
-- Paid by cheque. Missed Aug 2024 (no late fee — escalated to deposit).
-- ----------------------------------------
(3, 850.00, '2024-01-02 08:30:00', '2024-01-01', 'on_time', 'cheque', NULL, NULL),
(3, 850.00, '2024-02-02 09:00:00', '2024-02-01', 'on_time', 'cheque', NULL, NULL),
(3, 850.00, '2024-03-02 10:00:00', '2024-03-01', 'on_time', 'cheque', NULL, NULL),
(3, 850.00, '2024-04-02 09:00:00', '2024-04-01', 'on_time', 'cheque', NULL, NULL),
(3, 850.00, '2024-05-02 08:45:00', '2024-05-01', 'on_time', 'cheque', NULL, NULL),
(3, 850.00, '2024-06-02 09:30:00', '2024-06-01', 'on_time', 'cheque', NULL, NULL),
(3, 850.00, '2024-07-02 10:00:00', '2024-07-01', 'on_time', 'cheque', NULL, NULL),
(3, 850.00, '2024-08-03 12:00:00', '2024-08-01', 'missed',  'cheque', NULL, NULL),
(3, 850.00, '2024-09-02 09:00:00', '2024-09-01', 'on_time', 'cheque', NULL, NULL),
(3, 850.00, '2024-10-02 10:00:00', '2024-10-01', 'on_time', 'cheque', NULL, NULL),

-- ----------------------------------------
-- Lease 4: Emily Rodriguez | R4 | $700 | Jan 2024–Feb 2026
-- Auto-debit — always pays on exactly the due date.
-- ----------------------------------------
(4, 700.00, '2024-01-01 18:00:00', '2024-01-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2024-02-01 17:30:00', '2024-02-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2024-03-01 18:00:00', '2024-03-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2024-04-01 17:00:00', '2024-04-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2024-05-01 18:30:00', '2024-05-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2024-06-01 17:00:00', '2024-06-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2024-07-01 18:00:00', '2024-07-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2024-08-01 17:30:00', '2024-08-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2024-09-01 18:00:00', '2024-09-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2024-10-01 17:00:00', '2024-10-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2024-11-01 18:00:00', '2024-11-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2024-12-01 17:30:00', '2024-12-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2025-01-01 18:00:00', '2025-01-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2025-02-01 17:00:00', '2025-02-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2025-03-01 18:30:00', '2025-03-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2025-04-01 17:00:00', '2025-04-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2025-05-01 18:00:00', '2025-05-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2025-06-01 17:30:00', '2025-06-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2025-07-01 18:00:00', '2025-07-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2025-08-01 17:00:00', '2025-08-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2025-09-01 18:00:00', '2025-09-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2025-10-01 17:30:00', '2025-10-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2025-11-01 18:00:00', '2025-11-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2025-12-01 17:00:00', '2025-12-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2026-01-01 18:30:00', '2026-01-01', 'on_time', 'auto-debit', NULL, NULL),
(4, 700.00, '2026-02-01 17:00:00', '2026-02-01', 'on_time', 'auto-debit', NULL, NULL),

-- ----------------------------------------
-- Lease 5: David Kim | R5 | $750 | Jan–May 2024 | always on time | e-transfer
-- ----------------------------------------
(5, 750.00, '2024-01-02 11:00:00', '2024-01-01', 'on_time', 'e-transfer', NULL, NULL),
(5, 750.00, '2024-02-02 10:30:00', '2024-02-01', 'on_time', 'e-transfer', NULL, NULL),
(5, 750.00, '2024-03-02 11:00:00', '2024-03-01', 'on_time', 'e-transfer', NULL, NULL),
(5, 750.00, '2024-04-02 10:00:00', '2024-04-01', 'on_time', 'e-transfer', NULL, NULL),
(5, 750.00, '2024-05-02 11:30:00', '2024-05-01', 'on_time', 'e-transfer', NULL, NULL),

-- ----------------------------------------
-- Lease 6: Priya Patel | R6 | $900 | Jan 2024–Feb 2026
-- Auto-debit — always pays on exactly the due date.
-- ----------------------------------------
(6, 900.00, '2024-01-01 20:00:00', '2024-01-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2024-02-01 19:30:00', '2024-02-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2024-03-01 20:00:00', '2024-03-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2024-04-01 19:00:00', '2024-04-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2024-05-01 20:30:00', '2024-05-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2024-06-01 19:00:00', '2024-06-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2024-07-01 20:00:00', '2024-07-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2024-08-01 19:30:00', '2024-08-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2024-09-01 20:00:00', '2024-09-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2024-10-01 19:00:00', '2024-10-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2024-11-01 20:00:00', '2024-11-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2024-12-01 19:30:00', '2024-12-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2025-01-01 20:00:00', '2025-01-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2025-02-01 19:00:00', '2025-02-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2025-03-01 20:30:00', '2025-03-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2025-04-01 19:00:00', '2025-04-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2025-05-01 20:00:00', '2025-05-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2025-06-01 19:30:00', '2025-06-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2025-07-01 20:00:00', '2025-07-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2025-08-01 19:00:00', '2025-08-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2025-09-01 20:00:00', '2025-09-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2025-10-01 19:30:00', '2025-10-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2025-11-01 20:00:00', '2025-11-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2025-12-01 19:00:00', '2025-12-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2026-01-01 20:30:00', '2026-01-01', 'on_time', 'auto-debit', NULL, NULL),
(6, 900.00, '2026-02-01 19:00:00', '2026-02-01', 'on_time', 'auto-debit', NULL, NULL),

-- ----------------------------------------
-- Lease 7: Tyler Brooks | R7 | $750 | Jan 2024–Feb 2026
-- 9 late payments. $50 late fee charged each time.
-- First 5 late fees collected; last 4 waived (landlord gave up pursuing).
-- Late months: Feb/Apr/Jun/Sep 2024, Jan/Mar/Jun/Oct/Dec 2025
-- ----------------------------------------
(7, 750.00, '2024-01-02 13:00:00', '2024-01-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2024-02-09 16:00:00', '2024-02-01', 'late',    'e-transfer', 50.00, 50.00),  -- fee collected
(7, 750.00, '2024-03-02 12:00:00', '2024-03-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2024-04-12 17:00:00', '2024-04-01', 'late',    'e-transfer', 50.00, 50.00),  -- fee collected
(7, 750.00, '2024-05-02 13:00:00', '2024-05-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2024-06-08 15:30:00', '2024-06-01', 'late',    'e-transfer', 50.00, 50.00),  -- fee collected
(7, 750.00, '2024-07-02 12:30:00', '2024-07-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2024-08-02 13:00:00', '2024-08-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2024-09-10 16:00:00', '2024-09-01', 'late',    'e-transfer', 50.00, 50.00),  -- fee collected
(7, 750.00, '2024-10-02 12:00:00', '2024-10-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2024-11-02 13:30:00', '2024-11-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2024-12-02 12:00:00', '2024-12-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2025-01-11 17:00:00', '2025-01-01', 'late',    'e-transfer', 50.00, 50.00),  -- fee collected (5th and last)
(7, 750.00, '2025-02-02 13:00:00', '2025-02-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2025-03-09 15:30:00', '2025-03-01', 'late',    'e-transfer', 50.00, 0.00),   -- fee charged, waived
(7, 750.00, '2025-04-02 12:00:00', '2025-04-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2025-05-02 13:00:00', '2025-05-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2025-06-08 16:00:00', '2025-06-01', 'late',    'e-transfer', 50.00, 0.00),   -- fee charged, waived
(7, 750.00, '2025-07-02 12:30:00', '2025-07-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2025-08-02 13:00:00', '2025-08-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2025-09-02 12:00:00', '2025-09-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2025-10-12 17:30:00', '2025-10-01', 'late',    'e-transfer', 50.00, 0.00),   -- fee charged, waived
(7, 750.00, '2025-11-02 13:00:00', '2025-11-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2025-12-10 16:00:00', '2025-12-01', 'late',    'e-transfer', 50.00, 0.00),   -- fee charged, waived
(7, 750.00, '2026-01-02 12:00:00', '2026-01-01', 'on_time', 'e-transfer', NULL,  NULL),
(7, 750.00, '2026-02-02 13:00:00', '2026-02-01', 'on_time', 'e-transfer', NULL,  NULL),

-- ----------------------------------------
-- Lease 8: Aisha Mahmoud | R8 | $650 | Jan 2024–Feb 2026 | always on time | e-transfer
-- ----------------------------------------
(8, 650.00, '2024-01-01 16:00:00', '2024-01-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2024-02-01 15:30:00', '2024-02-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2024-03-01 16:00:00', '2024-03-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2024-04-01 15:00:00', '2024-04-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2024-05-01 16:30:00', '2024-05-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2024-06-01 15:00:00', '2024-06-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2024-07-01 16:00:00', '2024-07-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2024-08-01 15:30:00', '2024-08-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2024-09-01 16:00:00', '2024-09-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2024-10-01 15:00:00', '2024-10-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2024-11-01 16:00:00', '2024-11-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2024-12-01 15:30:00', '2024-12-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2025-01-01 16:00:00', '2025-01-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2025-02-01 15:00:00', '2025-02-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2025-03-01 16:30:00', '2025-03-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2025-04-01 15:00:00', '2025-04-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2025-05-01 16:00:00', '2025-05-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2025-06-01 15:30:00', '2025-06-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2025-07-01 16:00:00', '2025-07-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2025-08-01 15:00:00', '2025-08-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2025-09-01 16:00:00', '2025-09-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2025-10-01 15:30:00', '2025-10-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2025-11-01 16:00:00', '2025-11-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2025-12-01 15:00:00', '2025-12-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2026-01-01 16:30:00', '2026-01-01', 'on_time', 'e-transfer', NULL, NULL),
(8, 650.00, '2026-02-01 15:00:00', '2026-02-01', 'on_time', 'e-transfer', NULL, NULL),

-- ----------------------------------------
-- Lease 9: Lucas Nguyen | R3 | $875 | Nov 2024–Feb 2026 | always on time | e-transfer
-- ----------------------------------------
(9, 875.00, '2024-11-02 10:00:00', '2024-11-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2024-12-02 10:00:00', '2024-12-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2025-01-02 10:00:00', '2025-01-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2025-02-02 10:00:00', '2025-02-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2025-03-02 10:00:00', '2025-03-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2025-04-02 10:00:00', '2025-04-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2025-05-02 10:00:00', '2025-05-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2025-06-02 10:00:00', '2025-06-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2025-07-02 10:00:00', '2025-07-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2025-08-02 10:00:00', '2025-08-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2025-09-02 10:00:00', '2025-09-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2025-10-02 10:00:00', '2025-10-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2025-11-02 10:00:00', '2025-11-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2025-12-02 10:00:00', '2025-12-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2026-01-02 10:00:00', '2026-01-01', 'on_time', 'e-transfer', NULL, NULL),
(9, 875.00, '2026-02-02 10:00:00', '2026-02-01', 'on_time', 'e-transfer', NULL, NULL),

-- ----------------------------------------
-- Lease 10: Olivia Tremblay | R5 | $775 | Sep 2024–Feb 2026
-- Auto-debit — always pays on exactly the due date.
-- ----------------------------------------
(10, 775.00, '2024-09-01 11:00:00', '2024-09-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2024-10-01 11:00:00', '2024-10-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2024-11-01 11:00:00', '2024-11-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2024-12-01 11:00:00', '2024-12-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2025-01-01 11:00:00', '2025-01-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2025-02-01 11:00:00', '2025-02-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2025-03-01 11:00:00', '2025-03-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2025-04-01 11:00:00', '2025-04-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2025-05-01 11:00:00', '2025-05-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2025-06-01 11:00:00', '2025-06-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2025-07-01 11:00:00', '2025-07-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2025-08-01 11:00:00', '2025-08-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2025-09-01 11:00:00', '2025-09-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2025-10-01 11:00:00', '2025-10-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2025-11-01 11:00:00', '2025-11-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2025-12-01 11:00:00', '2025-12-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2026-01-01 11:00:00', '2026-01-01', 'on_time', 'auto-debit', NULL, NULL),
(10, 775.00, '2026-02-01 11:00:00', '2026-02-01', 'on_time', 'auto-debit', NULL, NULL);


-- ============================================
-- 6. EXPENSES
-- ============================================
-- opex = deduct in full this year. capex = creates an asset, depreciate via CCA.
-- expense_id 56 (R5 refrigerator) is referenced in the assets table.
-- IDs run 1–9 (property_tax), 10–11 (insurance), 12–37 (management),
-- 38–45 (utilities), 46–51 (property-wide maintenance), 52–59 (unit-specific).

INSERT INTO expenses (property_id, unit_id, category, expense_class, description, amount, expense_date) VALUES

-- PROPERTY TAX: quarterly, property-wide (opex — fully deductible per T776)
(1, NULL, 'property_tax', 'opex', 'Q1 2024 municipal property tax', 1800.00, '2024-01-15'),
(1, NULL, 'property_tax', 'opex', 'Q2 2024 municipal property tax', 1800.00, '2024-04-15'),
(1, NULL, 'property_tax', 'opex', 'Q3 2024 municipal property tax', 1800.00, '2024-07-15'),
(1, NULL, 'property_tax', 'opex', 'Q4 2024 municipal property tax', 1800.00, '2024-10-15'),
(1, NULL, 'property_tax', 'opex', 'Q1 2025 municipal property tax', 1850.00, '2025-01-15'),
(1, NULL, 'property_tax', 'opex', 'Q2 2025 municipal property tax', 1850.00, '2025-04-15'),
(1, NULL, 'property_tax', 'opex', 'Q3 2025 municipal property tax', 1850.00, '2025-07-15'),
(1, NULL, 'property_tax', 'opex', 'Q4 2025 municipal property tax', 1850.00, '2025-10-15'),
(1, NULL, 'property_tax', 'opex', 'Q1 2026 municipal property tax', 1875.00, '2026-01-15'),

-- INSURANCE: annual landlord policy, property-wide (opex)
(1, NULL, 'insurance', 'opex', 'Annual landlord insurance 2024', 2400.00, '2024-01-10'),
(1, NULL, 'insurance', 'opex', 'Annual landlord insurance 2025', 2520.00, '2025-01-10'),

-- MANAGEMENT FEE: monthly flat fee, property-wide (opex)
(1, NULL, 'management', 'opex', 'Property management fee Jan 2024', 350.00, '2024-01-31'),
(1, NULL, 'management', 'opex', 'Property management fee Feb 2024', 350.00, '2024-02-29'),
(1, NULL, 'management', 'opex', 'Property management fee Mar 2024', 350.00, '2024-03-31'),
(1, NULL, 'management', 'opex', 'Property management fee Apr 2024', 350.00, '2024-04-30'),
(1, NULL, 'management', 'opex', 'Property management fee May 2024', 350.00, '2024-05-31'),
(1, NULL, 'management', 'opex', 'Property management fee Jun 2024', 350.00, '2024-06-30'),
(1, NULL, 'management', 'opex', 'Property management fee Jul 2024', 350.00, '2024-07-31'),
(1, NULL, 'management', 'opex', 'Property management fee Aug 2024', 350.00, '2024-08-31'),
(1, NULL, 'management', 'opex', 'Property management fee Sep 2024', 350.00, '2024-09-30'),
(1, NULL, 'management', 'opex', 'Property management fee Oct 2024', 350.00, '2024-10-31'),
(1, NULL, 'management', 'opex', 'Property management fee Nov 2024', 350.00, '2024-11-30'),
(1, NULL, 'management', 'opex', 'Property management fee Dec 2024', 350.00, '2024-12-31'),
(1, NULL, 'management', 'opex', 'Property management fee Jan 2025', 350.00, '2025-01-31'),
(1, NULL, 'management', 'opex', 'Property management fee Feb 2025', 350.00, '2025-02-28'),
(1, NULL, 'management', 'opex', 'Property management fee Mar 2025', 350.00, '2025-03-31'),
(1, NULL, 'management', 'opex', 'Property management fee Apr 2025', 350.00, '2025-04-30'),
(1, NULL, 'management', 'opex', 'Property management fee May 2025', 350.00, '2025-05-31'),
(1, NULL, 'management', 'opex', 'Property management fee Jun 2025', 350.00, '2025-06-30'),
(1, NULL, 'management', 'opex', 'Property management fee Jul 2025', 350.00, '2025-07-31'),
(1, NULL, 'management', 'opex', 'Property management fee Aug 2025', 350.00, '2025-08-31'),
(1, NULL, 'management', 'opex', 'Property management fee Sep 2025', 350.00, '2025-09-30'),
(1, NULL, 'management', 'opex', 'Property management fee Oct 2025', 350.00, '2025-10-31'),
(1, NULL, 'management', 'opex', 'Property management fee Nov 2025', 350.00, '2025-11-30'),
(1, NULL, 'management', 'opex', 'Property management fee Dec 2025', 350.00, '2025-12-31'),
(1, NULL, 'management', 'opex', 'Property management fee Jan 2026', 350.00, '2026-01-31'),
(1, NULL, 'management', 'opex', 'Property management fee Feb 2026', 350.00, '2026-02-28'),

-- UTILITIES: common area hydro, quarterly, property-wide (opex)
(1, NULL, 'utilities', 'opex', 'Common area hydro Q1 2024', 320.00, '2024-03-31'),
(1, NULL, 'utilities', 'opex', 'Common area hydro Q2 2024', 285.00, '2024-06-30'),
(1, NULL, 'utilities', 'opex', 'Common area hydro Q3 2024', 310.00, '2024-09-30'),
(1, NULL, 'utilities', 'opex', 'Common area hydro Q4 2024', 340.00, '2024-12-31'),
(1, NULL, 'utilities', 'opex', 'Common area hydro Q1 2025', 330.00, '2025-03-31'),
(1, NULL, 'utilities', 'opex', 'Common area hydro Q2 2025', 295.00, '2025-06-30'),
(1, NULL, 'utilities', 'opex', 'Common area hydro Q3 2025', 315.00, '2025-09-30'),
(1, NULL, 'utilities', 'opex', 'Common area hydro Q4 2025', 350.00, '2025-12-31'),

-- PROPERTY-WIDE MAINTENANCE (opex — routine repairs and upkeep, not capital improvements)
(1, NULL, 'maintenance', 'opex', 'Snow removal Jan 2024',                  180.00, '2024-01-20'),
(1, NULL, 'maintenance', 'opex', 'Landscaping and yard cleanup May 2024',  280.00, '2024-05-12'),
(1, NULL, 'maintenance', 'opex', 'Roof inspection and minor repairs',     1200.00, '2024-07-18'),
(1, NULL, 'maintenance', 'opex', 'Snow removal Feb 2025',                  195.00, '2025-02-08'),
(1, NULL, 'maintenance', 'opex', 'Landscaping and yard cleanup May 2025',  295.00, '2025-05-10'),
(1, NULL, 'maintenance', 'opex', 'Exterior painting Aug 2025',            1800.00, '2025-08-15'),

-- UNIT-SPECIFIC MAINTENANCE
-- R1–R4, R6–R8: routine repairs = opex (restores to original condition, no new asset created)
-- R5 refrigerator: capex (new appliance = new asset; depreciated via CCA Class 8 at 20%)
(1, 1, 'maintenance', 'opex',   'Plumbing repair - R1 bathroom sink',          320.00, '2024-03-15'),  -- ID 52
(1, 2, 'maintenance', 'opex',   'Interior painting - R2 walls and ceiling',    280.00, '2024-08-22'),  -- ID 53
(1, 3, 'maintenance', 'opex',   'Deep cleaning after tenant departure - R3',   180.00, '2024-11-05'),  -- ID 54
(1, 4, 'maintenance', 'opex',   'Window latch repair - R4',                    240.00, '2025-02-14'),  -- ID 55
(1, 5, 'maintenance', 'capex',  'Refrigerator replacement - R5',               680.00, '2024-08-08'),  -- ID 56 ← capex, see assets table
(1, 6, 'maintenance', 'opex',   'Stovetop repair - R6',                        195.00, '2025-05-20'),  -- ID 57
(1, 7, 'maintenance', 'opex',   'Hardwood floor repair - R7',                  450.00, '2024-06-10'),  -- ID 58
(1, 8, 'maintenance', 'opex',   'General maintenance and touch-ups - R8',      160.00, '2025-09-22');  -- ID 59


-- ============================================
-- 7. ASSETS
-- ============================================
-- Two assets: the building (Class 1, 4%) and the R5 fridge (Class 8, 20%).
-- Building acquired Sep 2019 — before the tracking period, so expense_id is NULL.
-- UCC (Undepreciated Capital Cost) = original cost minus all CCA claimed so far.
-- Half-year rule applies in the year of acquisition: CCA × 50% in year 1.
--   Building:  4% × $320,000 × 50% = $6,400 (year 1)
--   Fridge:   20% × $680     × 50% = $68    (2024), 20% × $612 = $122.40 (2025)

INSERT INTO assets (property_id, unit_id, expense_id, description, cca_class, cca_rate,
                    acquisition_date, acquisition_cost, salvage_value, disposal_date, disposal_amount) VALUES
(1, NULL, NULL, '142 Maple Street residential building',
 'class_1', 0.0400, '2019-09-01', 320000.00, 0.00, NULL, NULL),

(1, 5, 56, 'Refrigerator - Room R5',
 'class_8', 0.2000, '2024-08-08', 680.00, 0.00, NULL, NULL);
