-- Clip V2.1: the clustered index and a nonclustered index of Enrollment.Invoice, what each
-- one holds, and why the page of the invoices of a company reads three pages per invoice.
-- Runs on the lab, in one session, after 00-setup.sql. Reads only. Turn on the actual plan
-- in SSMS (Ctrl+M); the pages read are in the Messages tab.
USE PachadataTraining;
GO
-- 1. The indexes of Enrollment.Invoice and their columns. pk_Invoice is the clustered index:
--    its key is InvoiceCode, a varchar(50). nix_invoice_companyid has CompanyId alone.
SELECT i.name AS IndexName, i.type_desc AS IndexType, c.name AS ColumnName,
       ic.key_ordinal, ic.is_included_column
FROM sys.indexes AS i
JOIN sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns AS c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID(N'Enrollment.Invoice')
ORDER BY i.index_id, ic.key_ordinal;
GO
-- 2. The page of the website, for company 100 (10 invoices).
SET STATISTICS IO ON;
GO
EXEC Enrollment.GetCompanyInvoices @CompanyId = 100;
GO
SET STATISTICS IO OFF;
GO
-- 3. The two trees, level by level. Level 0 is the leaf. The leaf of pk_Invoice is the
--    table itself: the whole row, 78 bytes on average. The leaf of nix_invoice_companyid
--    holds 25 bytes per invoice: CompanyId and InvoiceCode.
SELECT i.name AS IndexName, s.index_depth, s.index_level, s.page_count, s.record_count,
       CAST(s.avg_record_size_in_bytes AS decimal(6, 1)) AS avg_record_size
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'Enrollment.Invoice'), NULL, NULL,
                                    'DETAILED') AS s
JOIN sys.indexes AS i ON i.object_id = s.object_id AND i.index_id = s.index_id
ORDER BY s.index_id, s.index_level DESC;
GO
-- 4. The root page of nix_invoice_companyid, read with DBCC PAGE (undocumented, on the lab
--    only). The last result set lists its rows: the key is CompanyId, then InvoiceCode,
--    the key of the clustered index, added because the index is not unique.
DECLARE @db int = DB_ID(), @file int, @page int;
SELECT @file = allocated_page_file_id, @page = allocated_page_page_id
FROM sys.dm_db_database_page_allocations(DB_ID(), OBJECT_ID(N'Enrollment.Invoice'),
         INDEXPROPERTY(OBJECT_ID(N'Enrollment.Invoice'), N'nix_invoice_companyid', 'IndexID'),
         NULL, 'DETAILED')
WHERE page_type_desc = N'INDEX_PAGE' AND page_level = 2;
DBCC PAGE (@db, @file, @page, 3) WITH TABLERESULTS, NO_INFOMSGS;
GO
-- 5. What the nonclustered index answers alone: the codes of the invoices of company 100.
--    InvoiceCode is in its leaf, no lookup. Then one invoice by its code, in the clustered
--    index: three pages, one per level.
SET STATISTICS IO ON;
GO
SELECT InvoiceCode
FROM Enrollment.Invoice
WHERE CompanyId = 100;

SELECT InvoiceCode, InvoiceDate, DueDate, GrossAmount, ReminderLevel
FROM Enrollment.Invoice
WHERE InvoiceCode = 'FA2025-008211';
GO
SET STATISTICS IO OFF;
GO
