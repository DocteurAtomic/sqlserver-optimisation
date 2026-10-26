-- Module V7, clip 5: optimized locking. Runs on the lab, in one session, after
-- 03d-continuous-numbering.sql (row versioning is ON).
-- Turns on accelerated database recovery (ADR), then optimized locking, on the base, then
-- counts the locks the same updates hold as in step 3 of 01-locks-and-isolation.sql. Every
-- transaction is rolled back. Stop the load first: both ALTER DATABASE need the base alone.
USE master;
GO
ALTER DATABASE PachadataTraining SET ACCELERATED_DATABASE_RECOVERY = ON WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE PachadataTraining SET OPTIMIZED_LOCKING = ON WITH ROLLBACK IMMEDIATE;
GO
USE PachadataTraining;
GO
SET NOCOUNT ON;
SELECT name, is_read_committed_snapshot_on, is_accelerated_database_recovery_on,
       is_optimized_locking_on
FROM sys.databases
WHERE name = DB_NAME();
GO
-- Step 1. One invoice updated in an open transaction: the locks it holds now.
BEGIN TRANSACTION;
UPDATE Enrollment.Invoice
SET ReminderLevel = 0, ReminderDate = NULL
WHERE InvoiceCode = 'FA2026-007400';
SELECT resource_type, request_mode, request_status, COUNT(*) AS locks
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID AND resource_database_id = DB_ID()
GROUP BY resource_type, request_mode, request_status
ORDER BY resource_type;
ROLLBACK;
GO
-- Step 2. The same updates as step 3 of 01-locks-and-isolation.sql.
SET ANSI_WARNINGS OFF;
DECLARE @rows int;
DECLARE @r TABLE (rows_updated int, key_locks int, page_locks int, table_x_lock int,
                  xact_locks int, all_locks int);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT v FROM (VALUES (1000), (5000), (6114), (6115), (110737)) AS t(v);
OPEN c;
FETCH NEXT FROM c INTO @rows;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRANSACTION;
    UPDATE TOP (@rows) Enrollment.Invoice SET ReminderLevel = 3 - ReminderLevel;
    INSERT @r
    SELECT @rows,
           SUM(CASE WHEN resource_type = 'KEY' THEN 1 ELSE 0 END),
           SUM(CASE WHEN resource_type = 'PAGE' THEN 1 ELSE 0 END),
           COUNT(DISTINCT CASE WHEN resource_type = 'OBJECT' AND request_mode = 'X'
                               THEN resource_associated_entity_id END),
           SUM(CASE WHEN resource_type = 'XACT' THEN 1 ELSE 0 END),
           -- The schema lock (METADATA) of the first compilation left aside.
           SUM(CASE WHEN resource_type <> 'METADATA' THEN 1 ELSE 0 END)
    FROM sys.dm_tran_locks
    WHERE request_session_id = @@SPID AND resource_database_id = DB_ID();
    ROLLBACK;
    FETCH NEXT FROM c INTO @rows;
END;
CLOSE c;
DEALLOCATE c;
SET ANSI_WARNINGS ON;

SELECT rows_updated, key_locks, page_locks, table_x_lock, xact_locks, all_locks
FROM @r
ORDER BY rows_updated;
GO
