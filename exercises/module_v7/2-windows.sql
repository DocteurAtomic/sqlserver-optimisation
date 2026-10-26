-- Exercise of module V7, the scenes of parts 2 and 3, each in two query windows. Runs on
-- the lab, after 1-start.sql.
-- ci: skip (several sessions: paste each part in its own window, as the README says)

-- Part 2, window A: a planner changes the price of a session of November, and leaves the
-- transaction open (ROLLBACK at the end of the part).
USE PachadataTraining;
BEGIN TRANSACTION;
UPDATE Course.Session SET Price = Price + 10 WHERE SessionId = 17660;
-- ROLLBACK;
GO

-- Part 2, window B: the sales team reads the sessions of November.
USE PachadataTraining;
SELECT COUNT(*) AS sessions, SUM(Price) AS catalog_value
FROM Course.Session
WHERE StartDate >= '20261101' AND StartDate < '20261201';
GO

-- Part 3, window A: a late payment fee on invoice FA2026-007300.
USE PachadataTraining;
EXEC Enrollment.AddInvoiceLine @InvoiceCode = 'FA2026-007300', @Label = 'Late payment fee',
     @Quantity = 1, @UnitPrice = 40;
GO

-- Part 3, window B, started a second after window A: a correction on the same invoice.
USE PachadataTraining;
EXEC Enrollment.AddInvoiceLine @InvoiceCode = 'FA2026-007300', @Label = 'Course material',
     @Quantity = 2, @UnitPrice = 25;
GO
