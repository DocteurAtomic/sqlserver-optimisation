-- Clip V2.4: what an index costs the code that writes. Space, then 1,000 invoices inserted
-- one by one and 1,000 reminders recorded, measured in log and in index rows written, with
-- the nonclustered indexes, without them, and with the index the optimizer suggested in clip
-- V2.2 created as well. Runs on the lab, in one session, after
-- 03-filtered-and-column-order.sql. Every write is rolled back; the indexes are left as
-- clip V2.3 left them.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The space: the pages of each index of Enrollment.Invoice.
SELECT i.name AS IndexName, SUM(p.used_page_count) AS Pages,
       CAST(SUM(p.used_page_count) * 8 / 1024.0 AS decimal(6, 1)) AS MB
FROM sys.indexes AS i
JOIN sys.dm_db_partition_stats AS p ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'Enrollment.Invoice')
GROUP BY i.index_id, i.name
ORDER BY i.index_id;
GO
-- The measuring procedure, for this script only. Inside one transaction, rolled back at the
-- end: 1,000 invoices inserted one by one, as the invoicing application does, copied from
-- existing invoices with new numbers; then one UPDATE that raises the reminder level of
-- 1,000 invoices. It returns the log written by each step and the leaf rows written in each
-- index (sys.dm_db_index_operational_stats), with the leaf pages each index had to
-- allocate: a page split, when the row goes into a full page.
CREATE OR ALTER PROCEDURE #MeasureWrites
    @Label varchar(30)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @src TABLE (n int PRIMARY KEY, InvoiceCode varchar(50));
    INSERT INTO @src
    SELECT TOP (1000) ROW_NUMBER() OVER (ORDER BY InvoiceCode), InvoiceCode
    FROM Enrollment.Invoice
    WHERE DocumentType = 'I' AND InvoiceDate >= '20250101'
    ORDER BY InvoiceCode;

    DECLARE @ops TABLE (step varchar(10), index_id int, ins bigint, upd bigint, del bigint, alloc bigint);
    DECLARE @log TABLE (step varchar(10), bytes bigint);
    DECLARE @n int = 1, @code varchar(50);

    BEGIN TRANSACTION;
    INSERT INTO @ops SELECT 'start', index_id, leaf_insert_count, leaf_update_count, leaf_delete_count,
           leaf_allocation_count
    FROM sys.dm_db_index_operational_stats(DB_ID(), OBJECT_ID(N'Enrollment.Invoice'), NULL, NULL);
    INSERT INTO @log SELECT 'start', database_transaction_log_bytes_used
    FROM sys.dm_tran_database_transactions
    WHERE transaction_id = CURRENT_TRANSACTION_ID() AND database_id = DB_ID();

    WHILE @n <= 1000
    BEGIN
        SELECT @code = InvoiceCode FROM @src WHERE n = @n;
        INSERT INTO Enrollment.Invoice (InvoiceCode, DiscountCode, Discount, CreationDate,
            InvoiceDate, ReminderLevel, ReminderDate, OrderReference, NetAmount, GrossAmount,
            VatRate, DocumentType, OriginalInvoiceCode, CompanyId, ContactId, DueDate, Reason,
            SessionId)
        SELECT 'FA2026-9' + RIGHT('00000' + CAST(@n AS varchar(5)), 5), DiscountCode, Discount,
            CreationDate, InvoiceDate, ReminderLevel, ReminderDate, OrderReference, NetAmount,
            GrossAmount, VatRate, DocumentType, OriginalInvoiceCode, CompanyId, ContactId,
            DueDate, Reason, SessionId
        FROM Enrollment.Invoice
        WHERE InvoiceCode = @code;
        SET @n += 1;
    END;

    INSERT INTO @ops SELECT 'insert', index_id, leaf_insert_count, leaf_update_count, leaf_delete_count,
           leaf_allocation_count
    FROM sys.dm_db_index_operational_stats(DB_ID(), OBJECT_ID(N'Enrollment.Invoice'), NULL, NULL);
    INSERT INTO @log SELECT 'insert', database_transaction_log_bytes_used
    FROM sys.dm_tran_database_transactions
    WHERE transaction_id = CURRENT_TRANSACTION_ID() AND database_id = DB_ID();

    -- The reminder run: 1,000 unpaid invoices of 2025 move up one level. 0 to 1 puts the row
    -- into the filtered index, 1 to 2 and 2 to 3 change it there.
    UPDATE TOP (1000) Enrollment.Invoice
    SET ReminderLevel = ReminderLevel + 1, ReminderDate = '20261020'
    WHERE DocumentType = 'I' AND ReminderLevel < 3
      AND InvoiceDate >= '20250101' AND InvoiceDate < '20260101';

    INSERT INTO @ops SELECT 'update', index_id, leaf_insert_count, leaf_update_count, leaf_delete_count,
           leaf_allocation_count
    FROM sys.dm_db_index_operational_stats(DB_ID(), OBJECT_ID(N'Enrollment.Invoice'), NULL, NULL);
    INSERT INTO @log SELECT 'update', database_transaction_log_bytes_used
    FROM sys.dm_tran_database_transactions
    WHERE transaction_id = CURRENT_TRANSACTION_ID() AND database_id = DB_ID();
    ROLLBACK TRANSACTION;

    SELECT @Label AS Indexes,
           (SELECT bytes FROM @log WHERE step = 'insert') - (SELECT bytes FROM @log WHERE step = 'start')
               AS InsertLogBytes,
           (SELECT bytes FROM @log WHERE step = 'update') - (SELECT bytes FROM @log WHERE step = 'insert')
               AS UpdateLogBytes;

    SELECT @Label AS Indexes, ISNULL(i.name, N'(heap)') AS IndexName,
           b.ins - a.ins AS RowsInsertedByInsert,
           b.alloc - a.alloc AS PagesAllocatedByInsert,
           (c.ins - b.ins) + (c.upd - b.upd) + (c.del - b.del) AS RowsWrittenByUpdate
    FROM @ops AS a
    JOIN @ops AS b ON b.index_id = a.index_id AND b.step = 'insert'
    JOIN @ops AS c ON c.index_id = a.index_id AND c.step = 'update'
    JOIN sys.indexes AS i ON i.object_id = OBJECT_ID(N'Enrollment.Invoice') AND i.index_id = a.index_id
    WHERE a.step = 'start'
    ORDER BY a.index_id;
END;
GO
-- 2. The table as clip V2.3 left it: the clustered index, the covering index of the page,
--    the filtered index of the reminders.
EXEC #MeasureWrites @Label = 'clustered + 2';
GO
-- 3. The clustered index alone: the two nonclustered indexes disabled. A disabled index is
--    not maintained; it keeps its definition, and REBUILD brings it back.
ALTER INDEX nix_invoice_companyid ON Enrollment.Invoice DISABLE;
ALTER INDEX nix_invoice_reminders ON Enrollment.Invoice DISABLE;
GO
EXEC #MeasureWrites @Label = 'clustered alone';
GO
ALTER INDEX nix_invoice_companyid ON Enrollment.Invoice REBUILD;
ALTER INDEX nix_invoice_reminders ON Enrollment.Invoice REBUILD;
GO
-- 4. The suggestion of clip V2.2 created as it was given, next to the index of the page:
--    a third nonclustered index, with the same first column.
CREATE INDEX nix_invoice_suggested ON Enrollment.Invoice (CompanyId)
    INCLUDE (InvoiceDate, ReminderLevel, GrossAmount, DueDate);
GO
EXEC #MeasureWrites @Label = 'clustered + 3';
GO
-- Which of the two does the page read? The optimizer picks one; the other is written at
-- every insert and read by nobody.
SET STATISTICS IO ON;
GO
EXEC Enrollment.GetCompanyInvoices @CompanyId = 1050;
GO
SET STATISTICS IO OFF;
GO
SELECT i.name AS IndexName, u.user_seeks, u.user_scans, u.user_lookups, u.user_updates
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_usage_stats AS u
    ON u.database_id = DB_ID() AND u.object_id = i.object_id AND u.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'Enrollment.Invoice')
ORDER BY i.index_id;
GO
DROP INDEX nix_invoice_suggested ON Enrollment.Invoice;
GO
