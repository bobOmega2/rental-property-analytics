SELECT 'payments' AS tbl, COUNT(*) FROM payments
UNION ALL
SELECT 'expenses', COUNT(*) FROM expenses
UNION ALL
SELECT 'assets',   COUNT(*) FROM assets;
