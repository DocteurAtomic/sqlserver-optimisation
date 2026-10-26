-- Clip V2.3: the order of the columns of a composite key, then a filtered index and the
-- parameter that keeps the optimizer from using it. Runs on the lab, in one session, after
-- 02-covering-index.sql. Changes the indexes of Enrollment.Invoice and creates the procedure
-- Enrollment.GetRemindedInvoices; 00-setup.sql of the next module restores the database.
-- Turn on the actual plan in SSMS (Ctrl+M); the pages read are in the Messages tab.
USE PachadataTraining;
SET ARITHABORT ON;
GO
-- 1. The statement of a year, on the customer area: the invoices of company 392 (the largest
--    customer, 3,016 invoices) in 2025. With the index of clip V2.2, key CompanyId: the
--    seek finds all the invoices of the company, the date is checked on each one.
SET STATISTICS IO ON;
GO
SELECT InvoiceCode, InvoiceDate, GrossAmount
FROM Enrollment.Invoice
WHERE CompanyId = 392
  AND InvoiceDate >= '20250101' AND InvoiceDate < '20260101'
ORDER BY InvoiceDate DESC;
GO
SET STATISTICS IO OFF;
GO
-- 2. A first idea: an index whose key starts with the date, then the company.
CREATE INDEX nix_invoice_date_company ON Enrollment.Invoice (InvoiceDate, CompanyId)
    INCLUDE (DueDate, GrossAmount, ReminderLevel);
GO
-- 3. The other order: nix_invoice_companyid gets InvoiceDate in its key, after CompanyId.
CREATE INDEX nix_invoice_companyid ON Enrollment.Invoice (CompanyId, InvoiceDate)
    INCLUDE (DueDate, GrossAmount, ReminderLevel)
    WITH (DROP_EXISTING = ON);
GO
-- 4. The same statement through each index, forced by a table hint for the comparison.
SET STATISTICS IO ON;
GO
SELECT InvoiceCode, InvoiceDate, GrossAmount
FROM Enrollment.Invoice WITH (INDEX (nix_invoice_date_company))
WHERE CompanyId = 392
  AND InvoiceDate >= '20250101' AND InvoiceDate < '20260101'
ORDER BY InvoiceDate DESC;

SELECT InvoiceCode, InvoiceDate, GrossAmount
FROM Enrollment.Invoice WITH (INDEX (nix_invoice_companyid))
WHERE CompanyId = 392
  AND InvoiceDate >= '20250101' AND InvoiceDate < '20260101'
ORDER BY InvoiceDate DESC;
GO
-- 5. The invoices of one day, for all the companies: the date alone. Through the index that
--    starts with the date, then through the one that starts with the company.
SELECT COUNT(*) AS Invoices
FROM Enrollment.Invoice WITH (INDEX (nix_invoice_date_company))
WHERE InvoiceDate >= '20250101' AND InvoiceDate < '20250201';

SELECT COUNT(*) AS Invoices
FROM Enrollment.Invoice WITH (INDEX (nix_invoice_companyid))
WHERE InvoiceDate >= '20250101' AND InvoiceDate < '20250201';
GO
-- 6. Two equalities: company 392 on 21 March 2024. 1,913 companies with invoices, 5,572
--    dates: the company is the less selective column, and the order does not change the
--    pages read.
SELECT COUNT(*) AS Invoices
FROM Enrollment.Invoice WITH (INDEX (nix_invoice_date_company))
WHERE CompanyId = 392 AND InvoiceDate = '20240321';

SELECT COUNT(*) AS Invoices
FROM Enrollment.Invoice WITH (INDEX (nix_invoice_companyid))
WHERE CompanyId = 392 AND InvoiceDate = '20240321';
GO
-- 7. The page of the website, for company 1050, with the new key: the invoices come out of
--    the index already in date order, read backwards. No Sort operator any more.
EXEC Enrollment.GetCompanyInvoices @CompanyId = 1050;
GO
SET STATISTICS IO OFF;
GO
-- No query of the site reads the invoices of a month for all the companies: the index that
-- starts with the date goes away.
DROP INDEX nix_invoice_date_company ON Enrollment.Invoice;
GO
-- 8. A filtered index for the reminder screen of accounting. 26,075 invoices have had at
--    least one reminder, out of 110,737.
CREATE INDEX nix_invoice_reminders ON Enrollment.Invoice (ReminderLevel)
    INCLUDE (CompanyId, InvoiceDate, GrossAmount, ReminderDate)
    WHERE ReminderLevel > 0;
GO
SELECT i.name AS IndexName, i.filter_definition, SUM(p.used_page_count) AS Pages,
       SUM(p.row_count) AS Rows
FROM sys.indexes AS i
JOIN sys.dm_db_partition_stats AS p ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'Enrollment.Invoice')
GROUP BY i.index_id, i.name, i.filter_definition
ORDER BY i.index_id;
GO
-- The screen, as the developer writes it: the reminder level is a parameter.
CREATE OR ALTER PROCEDURE Enrollment.GetRemindedInvoices
    @ReminderLevel tinyint
AS
BEGIN
    SET NOCOUNT ON;
    SELECT InvoiceCode, CompanyId, InvoiceDate, GrossAmount, ReminderDate
    FROM Enrollment.Invoice
    WHERE ReminderLevel = @ReminderLevel
    ORDER BY ReminderDate;
END;
GO
-- 9. The third reminders: with the value written in the query, then through the procedure.
SET STATISTICS IO ON;
GO
SELECT InvoiceCode, CompanyId, InvoiceDate, GrossAmount, ReminderDate
FROM Enrollment.Invoice
WHERE ReminderLevel = 3
ORDER BY ReminderDate;

EXEC Enrollment.GetRemindedInvoices @ReminderLevel = 3;
GO
-- The same query from a session with QUOTED_IDENTIFIER OFF, the default of sqlcmd without
-- -I and of some old drivers: a filtered index demands seven SET options, and the optimizer
-- ignores it when one differs. SSMS sets it ON.
SET QUOTED_IDENTIFIER OFF;
GO
SELECT InvoiceCode, CompanyId, InvoiceDate, GrossAmount, ReminderDate
FROM Enrollment.Invoice
WHERE ReminderLevel = 3
ORDER BY ReminderDate;
GO
SET QUOTED_IDENTIFIER ON;
GO
SET STATISTICS IO OFF;
GO
-- 10. The fix: the filter of the index repeated in the query. ReminderLevel > 0 is true for
--     every row the screen shows, whatever the value of the parameter, and now the plan
--     cached for one value is right for all: the filtered index can serve it. A call for
--     level 0 returns nothing, which the screen of reminders never asks for.
CREATE OR ALTER PROCEDURE Enrollment.GetRemindedInvoices
    @ReminderLevel tinyint
AS
BEGIN
    SET NOCOUNT ON;
    SELECT InvoiceCode, CompanyId, InvoiceDate, GrossAmount, ReminderDate
    FROM Enrollment.Invoice
    WHERE ReminderLevel = @ReminderLevel
      AND ReminderLevel > 0
    ORDER BY ReminderDate;
END;
GO
SET STATISTICS IO ON;
GO
EXEC Enrollment.GetRemindedInvoices @ReminderLevel = 3;
EXEC Enrollment.GetRemindedInvoices @ReminderLevel = 1;
GO
SET STATISTICS IO OFF;
GO
