-- Clip V2.4, the end of the module: the index of 00-setup.sql put back, the calls of the page
-- measured, then the index the module ends with, and the same calls. Runs on the lab, in one
-- session, after 04a-the-cost.sql. The measure on the load is 01a-the-load.sql, run again
-- with charge.sh after this script. 00-setup.sql of the next module restores the database.
USE PachadataTraining;
SET ARITHABORT ON;
GO
-- Before: nix_invoice_companyid as 00-setup.sql created it, key CompanyId, nothing included.
CREATE INDEX nix_invoice_companyid ON Enrollment.Invoice (CompanyId)
    WITH (DROP_EXISTING = ON);
GO
SET STATISTICS IO ON;
GO
EXEC Enrollment.GetCompanyInvoices @CompanyId = 100;   -- 10 invoices, compiles the plan
EXEC Enrollment.GetCompanyInvoices @CompanyId = 25;    -- 21 invoices
EXEC Enrollment.GetCompanyInvoices @CompanyId = 1050;  -- 2,120 invoices
GO
SET STATISTICS IO OFF;
GO
-- The fix: the key the page filters and sorts on, the columns it shows in INCLUDE.
CREATE INDEX nix_invoice_companyid ON Enrollment.Invoice (CompanyId, InvoiceDate)
    INCLUDE (DueDate, GrossAmount, ReminderLevel)
    WITH (DROP_EXISTING = ON);
GO
SET STATISTICS IO ON;
GO
EXEC Enrollment.GetCompanyInvoices @CompanyId = 100;
EXEC Enrollment.GetCompanyInvoices @CompanyId = 25;
EXEC Enrollment.GetCompanyInvoices @CompanyId = 1050;
GO
SET STATISTICS IO OFF;
GO
SELECT i.name AS IndexName, i.filter_definition, SUM(p.used_page_count) AS Pages
FROM sys.indexes AS i
JOIN sys.dm_db_partition_stats AS p ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'Enrollment.Invoice')
GROUP BY i.index_id, i.name, i.filter_definition
ORDER BY i.index_id;
GO
