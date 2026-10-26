-- Exercise of module V7, solution. Runs on the lab, in one session, after 1-start.sql.
-- The scenes of 2-windows.sql are played by hand; this script gives what they show, in
-- comments, and runs what one session can run. At the end, it drops
-- Enrollment.AddInvoiceLine and puts READ_COMMITTED_SNAPSHOT back ON, as delivered.
USE PachadataTraining;
GO
SET NOCOUNT ON;
GO
-- Part 1. Lock escalation on Course.Session (19,300 rows, 65 pages for 6,180 rows).
-- Measured on the lab: 6,180 rows updated hold 6,180 key locks and 65 page locks, 6,245 in
-- all; 6,190 rows hold one exclusive lock on the table. The engine escalates when it holds
-- about 6,250 locks on the table, keys and pages counted together (a first try at 5,000,
-- then every 1,250 more), not at a number of rows.
SET ANSI_WARNINGS OFF;
DECLARE @rows int;
DECLARE @r TABLE (rows_updated int, key_locks int, page_locks int, table_x_lock int);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT v FROM (VALUES (6180), (6190)) AS t(v);
OPEN c;
FETCH NEXT FROM c INTO @rows;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRANSACTION;
    UPDATE TOP (@rows) Course.Session SET Price = Price + 1;
    INSERT @r
    SELECT @rows,
           SUM(CASE WHEN resource_type = 'KEY' THEN 1 ELSE 0 END),
           SUM(CASE WHEN resource_type = 'PAGE' THEN 1 ELSE 0 END),
           COUNT(DISTINCT CASE WHEN resource_type = 'OBJECT' AND request_mode = 'X'
                               THEN resource_associated_entity_id END)
    FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID AND resource_database_id = DB_ID();
    ROLLBACK;
    FETCH NEXT FROM c INTO @rows;
END;
CLOSE c;
DEALLOCATE c;
SET ANSI_WARNINGS ON;
SELECT rows_updated, key_locks, page_locks, key_locks + page_locks AS locks, table_x_lock
FROM @r ORDER BY rows_updated;
GO
-- Part 1, SERIALIZABLE. On Price, a column with no index, the read scans the table: the
-- range locks of every key it reads pass the threshold, and the engine takes a shared lock
-- on the whole table (22 rows in sys.dm_tran_locks: one per lock partition, the engine
-- seeing 22 processors on this lab). On StartDate, the first column of an index, it locks
-- the 123 keys of November and the next one, 124 RangeS-S: only that range is protected.
DECLARE @n int;
DECLARE @held TABLE (predicate varchar(20), resource_type nvarchar(60), request_mode nvarchar(60), locks int);
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION;
SELECT @n = COUNT(*) FROM Course.Session WHERE Price > 3000;
INSERT @held SELECT 'Price', resource_type, request_mode, COUNT(*)
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID AND resource_database_id = DB_ID() AND resource_type <> 'METADATA'
GROUP BY resource_type, request_mode;
ROLLBACK;
BEGIN TRANSACTION;
SELECT @n = COUNT(*) FROM Course.Session WHERE StartDate >= '20261101' AND StartDate < '20261201';
INSERT @held SELECT 'StartDate', resource_type, request_mode, COUNT(*)
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID AND resource_database_id = DB_ID() AND resource_type <> 'METADATA'
GROUP BY resource_type, request_mode;
ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT predicate, resource_type, request_mode, locks FROM @held ORDER BY predicate, resource_type;
GO
-- Part 2. With READ_COMMITTED_SNAPSHOT OFF, window B waits for window A (4.2 s in the
-- measure, with a transaction kept five seconds); its request shows LCK_M_S and
-- blocking_session_id = the session of window A, whose input buffer is the UPDATE. The
-- query that finds it, from a third window:
SELECT r.session_id, r.wait_type, r.wait_time AS wait_ms, r.blocking_session_id,
       r.wait_resource, ib.event_info AS blocker_input_buffer
FROM sys.dm_exec_requests AS r
OUTER APPLY sys.dm_exec_input_buffer(r.blocking_session_id, NULL) AS ib
WHERE r.blocking_session_id <> 0;
-- With READ_COMMITTED_SNAPSHOT ON, window B answers at once (182 ms, the time of the
-- connection) with the committed price: 123 sessions, 183,400.00, the value before the
-- UPDATE of window A. The writer still holds its exclusive lock: a second writer on session
-- 17660 would wait.
GO
-- Part 3. Two windows, one second apart, on the same invoice: window B fails with error
-- 2627 on pk_InvoiceLine, with or without row versioning. Both read the same MAX before
-- either inserts, since the pricing call comes between the read and the insert: the
-- shared lock of a READ COMMITTED read is released as soon as the row is read, and under
-- row versioning there is no lock at all.
-- A sequence does not fit: the numbers restart at 1 on each invoice. The fix serializes
-- the additions to one invoice: the transaction starts by locking the row of the invoice,
-- which it updates anyway at the end. Window B then waits for window A (about two seconds)
-- and reads the next number. Two additions to two different invoices do not wait for each
-- other. SERIALIZABLE on the MAX read would not do: both sessions keep a shared range lock,
-- each insert waits for the other one, and one of them is the victim of a deadlock (1205).
CREATE OR ALTER PROCEDURE Enrollment.AddInvoiceLine
    @InvoiceCode varchar(50),
    @Label varchar(200),
    @Quantity decimal(9, 2),
    @UnitPrice decimal(9, 2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @LineNumber smallint, @NetAmount decimal(9, 2) = ROUND(@Quantity * @UnitPrice, 2);

    BEGIN TRANSACTION;
        -- One addition at a time per invoice: the update lock on its row is kept until the
        -- end of the transaction.
        IF NOT EXISTS (SELECT 1 FROM Enrollment.Invoice WITH (UPDLOCK, HOLDLOCK)
                       WHERE InvoiceCode = @InvoiceCode)
            THROW 50151, 'Unknown invoice.', 1;

        SELECT @LineNumber = ISNULL(MAX(LineNumber), 0) + 1
        FROM Enrollment.InvoiceLine
        WHERE InvoiceCode = @InvoiceCode;

        -- The line is priced here, by the pricing service.
        WAITFOR DELAY '00:00:02';

        INSERT Enrollment.InvoiceLine (InvoiceCode, LineNumber, LineTypeCode, EnrollmentId,
                                       Label, Quantity, UnitPrice, NetAmount)
        VALUES (@InvoiceCode, @LineNumber, 'FEE', NULL, @Label, @Quantity, @UnitPrice, @NetAmount);

        UPDATE Enrollment.Invoice
        SET NetAmount = NetAmount + @NetAmount,
            GrossAmount = ROUND((NetAmount + @NetAmount) * (1 + VatRate / 100), 2)
        WHERE InvoiceCode = @InvoiceCode;
    COMMIT;

    SELECT @InvoiceCode AS InvoiceCode, @LineNumber AS LineNumber;
END;
GO
-- Measured with the two windows of part 3 played again: window A gets the next line
-- number, window B waits about two seconds (3.3 s for the whole window) and gets the one
-- after, no error.
-- The pricing call still sits inside the transaction: the two seconds are the time an
-- addition holds the invoice. Pricing the line before BEGIN TRANSACTION shortens it.
-- Cleanup. Play part 3 of 2-windows.sql again before running it.
DROP PROCEDURE IF EXISTS Enrollment.AddInvoiceLine;
GO
USE master;
GO
ALTER DATABASE PachadataTraining SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO
