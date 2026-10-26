-- Module V7, clip 1: locks and isolation levels. Runs on the lab, in one session, after
-- 00-setup.sql (READ_COMMITTED_SNAPSHOT is OFF: readers take shared locks).
-- Every transaction is rolled back: the script changes nothing.
USE PachadataTraining;
GO
SET NOCOUNT ON;
GO
-- Step 1. One invoice updated in an open transaction: the locks it holds.
BEGIN TRANSACTION;

UPDATE Enrollment.Invoice
SET ReminderLevel = 0, ReminderDate = NULL
WHERE InvoiceCode = 'FA2026-007400';

SELECT tl.resource_type,
       tl.resource_description,
       CASE tl.resource_type
           WHEN 'OBJECT' THEN OBJECT_SCHEMA_NAME(tl.resource_associated_entity_id) + '.'
                              + OBJECT_NAME(tl.resource_associated_entity_id)
           ELSE OBJECT_SCHEMA_NAME(p.object_id) + '.' + OBJECT_NAME(p.object_id)
       END AS object_name,
       tl.request_mode,
       tl.request_status
FROM sys.dm_tran_locks AS tl
LEFT JOIN sys.partitions AS p
    ON p.hobt_id = tl.resource_associated_entity_id
   AND tl.resource_type IN ('KEY', 'PAGE', 'RID', 'HOBT')
WHERE tl.request_session_id = @@SPID
  AND tl.resource_database_id = DB_ID()
ORDER BY CASE tl.resource_type WHEN 'KEY' THEN 1 WHEN 'PAGE' THEN 2 WHEN 'OBJECT' THEN 3 ELSE 4 END;

ROLLBACK;
GO
-- Step 2. The same read of ten sessions under three isolation levels: the locks still
-- held when the SELECT is over, inside the transaction.
DECLARE @n int;
DECLARE @held TABLE (isolation_level varchar(20), resource_type nvarchar(60),
                     request_mode nvarchar(60), locks int);

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION;
SELECT @n = COUNT(*) FROM (SELECT TOP (10) SessionId FROM Course.Session ORDER BY SessionId) AS s;
INSERT @held
SELECT 'READ COMMITTED', resource_type, request_mode, COUNT(*)
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID AND resource_database_id = DB_ID()
GROUP BY resource_type, request_mode;
ROLLBACK;

SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION;
SELECT @n = COUNT(*) FROM (SELECT TOP (10) SessionId FROM Course.Session ORDER BY SessionId) AS s;
INSERT @held
SELECT 'REPEATABLE READ', resource_type, request_mode, COUNT(*)
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID AND resource_database_id = DB_ID()
GROUP BY resource_type, request_mode;
ROLLBACK;

-- SERIALIZABLE: the credit notes of 2026, a range of the primary key.
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION;
SELECT @n = COUNT(*) FROM Enrollment.Invoice WHERE InvoiceCode LIKE 'AV2026-%';
INSERT @held
SELECT 'SERIALIZABLE', resource_type, request_mode, COUNT(*)
FROM sys.dm_tran_locks
WHERE request_session_id = @@SPID AND resource_database_id = DB_ID()
GROUP BY resource_type, request_mode;
ROLLBACK;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

SELECT @n AS credit_notes_2026;
SELECT isolation_level, resource_type, request_mode, locks
FROM @held
ORDER BY CASE isolation_level WHEN 'READ COMMITTED' THEN 1 WHEN 'REPEATABLE READ' THEN 2 ELSE 3 END,
         resource_type;
GO
-- Step 3. Lock escalation: the same update on more and more invoices. The engine tries to
-- escalate when one statement holds 5,000 locks on an object, then every 1,250 more;
-- key and page locks both count.
SET ANSI_WARNINGS OFF;
DECLARE @rows int;
DECLARE @r TABLE (rows_updated int, key_locks int, page_locks int, table_x_lock int);
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
FROM @r
ORDER BY rows_updated;
GO
