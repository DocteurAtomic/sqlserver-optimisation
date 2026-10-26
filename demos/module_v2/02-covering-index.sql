-- Clip V2.2: the covering index. What the optimizer suggests, and when; the included columns
-- added to the index the page already uses; the measure, call by call. The measure on the
-- load is 01a-the-load.sql, run again with charge.sh after step 2. Runs on the lab, in one
-- session, after 01b-clustered-and-nonclustered.sql. Changes nix_invoice_companyid;
-- 00-setup.sql of the next module restores the database. Turn on the actual plan in SSMS
-- (Ctrl+M); the pages read are in the Messages tab.
USE PachadataTraining;
SET ARITHABORT ON;
GO
-- 1. The suggestions of the optimizer for this database. The plan in the cache, compiled
--    for 10 invoices, has left none, however many calls the page has made.
SELECT d.equality_columns, d.inequality_columns, d.included_columns, s.user_seeks,
       CAST(s.avg_user_impact AS decimal(5, 1)) AS avg_user_impact
FROM sys.dm_db_missing_index_details AS d
JOIN sys.dm_db_missing_index_groups AS g ON g.index_handle = d.index_handle
JOIN sys.dm_db_missing_index_group_stats AS s ON s.group_handle = g.index_group_handle
WHERE d.database_id = DB_ID();
GO
-- One of the biggest customers, company 1050 (2,120 invoices), first with the plan in the cache, then
-- compiled for itself (WITH RECOMPILE, for this call only).
SET STATISTICS IO ON;
GO
EXEC Enrollment.GetCompanyInvoices @CompanyId = 1050;
EXEC Enrollment.GetCompanyInvoices @CompanyId = 1050 WITH RECOMPILE;
GO
SET STATISTICS IO OFF;
GO
-- The plan that scans has left a suggestion: a new index on CompanyId, the four columns
-- in INCLUDE. Nothing says that nix_invoice_companyid already exists with the same key.
SELECT d.equality_columns, d.inequality_columns, d.included_columns, s.user_seeks,
       CAST(s.avg_user_impact AS decimal(5, 1)) AS avg_user_impact
FROM sys.dm_db_missing_index_details AS d
JOIN sys.dm_db_missing_index_groups AS g ON g.index_handle = d.index_handle
JOIN sys.dm_db_missing_index_group_stats AS s ON s.group_handle = g.index_group_handle
WHERE d.database_id = DB_ID();
GO
-- 2. The fix: the same index, with the columns the page reads at its leaf level only.
--    DROP_EXISTING replaces it in one operation: the page is never without an index.
SELECT SUM(used_page_count) AS PagesBefore
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'Enrollment.Invoice')
  AND index_id = INDEXPROPERTY(OBJECT_ID(N'Enrollment.Invoice'), N'nix_invoice_companyid', 'IndexID');

CREATE INDEX nix_invoice_companyid ON Enrollment.Invoice (CompanyId)
    INCLUDE (InvoiceDate, DueDate, GrossAmount, ReminderLevel)
    WITH (DROP_EXISTING = ON);
GO
-- 3. After: company 100, then company 1050. The procedure has recompiled by itself: its
--    index has changed.
SET STATISTICS IO ON;
GO
EXEC Enrollment.GetCompanyInvoices @CompanyId = 100;
EXEC Enrollment.GetCompanyInvoices @CompanyId = 1050;
GO
SET STATISTICS IO OFF;
GO
-- 4. The price: the leaf level holds four more columns. The levels above hold the key
--    only, as before.
SELECT s.index_level, s.page_count, CAST(s.avg_record_size_in_bytes AS decimal(6, 1)) AS avg_record_size
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'Enrollment.Invoice'),
         INDEXPROPERTY(OBJECT_ID(N'Enrollment.Invoice'), N'nix_invoice_companyid', 'IndexID'),
         NULL, 'DETAILED') AS s
ORDER BY s.index_level DESC;
GO
