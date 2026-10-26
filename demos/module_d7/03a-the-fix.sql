-- Clip D7.3, the fix. Runs on the lab, in one session, after charge.sh has played the night
-- and while accounting-ssms still holds its transaction.
-- ci: skip (it needs the sessions the night leaves, and a regressed plan in Query Store)
-- What the night did, revealed in the clip:
--   - accounting-ssms: BEGIN TRANSACTION, then an UPDATE of the due date of the 654 invoices
--     of October, never committed. Its X locks block Enrollment.RecordPayment (UPDLOCK on
--     the invoice), and its first log record keeps the log from being reused (SIMPLE
--     recovery): the e-learning import fills it, and it grows.
--   - maintenance: ALTER INDEX ALL ON Contact.Contact REBUILD, which recompiles
--     Contact.GetContactByName, then a call for N'Simon': the plan compiled for 782 rows
--     scans the table for every name.
-- The fix:
--   1. The head of the chain is ended by KILL: its transaction is rolled back. On a
--      production server, the accountant is called first: she may prefer to commit.
--   2. The payments import, unblocked, finishes its file.
--   3. The plan of the evening is forced for the search of the back office (module 4).
--   4. A checkpoint truncates the log.
-- Afterwards, "charge.sh stop" closes the SSMS window of the accountant on the client side,
-- and "charge.sh day" plays two minutes of the day after.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- Step 1. KILL the head of the chain, found as in 02a-blocking-now.sql.
DECLARE @head int = (
    SELECT TOP (1) r.blocking_session_id
    FROM sys.dm_exec_requests AS r
    WHERE r.blocking_session_id <> 0
      AND NOT EXISTS (SELECT 1 FROM sys.dm_exec_requests AS h
                      WHERE h.session_id = r.blocking_session_id AND h.blocking_session_id <> 0)
    ORDER BY r.wait_time DESC);
SELECT @head AS head_session, host_name FROM sys.dm_exec_sessions WHERE session_id = @head;
DECLARE @kill nvarchar(30) = N'KILL ' + CAST(@head AS nvarchar(10)) + N';';
EXEC (@kill);
GO
-- Step 2. Ten seconds later: who still waits, and the payments recorded since the evening.
WAITFOR DELAY '00:00:10';
SELECT COUNT(*) AS requests_blocked
FROM sys.dm_exec_requests WHERE blocking_session_id <> 0;
SELECT s.host_name, s.status, r.command
FROM sys.dm_exec_sessions AS s
LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
WHERE s.host_name IN (N'accounting-ssms', N'payments-import');
-- The payments of the load are of 1.00, dated October 18: WIRE for the bank file, CARD for
-- the customer area.
SELECT PaymentMethodCode, COUNT(*) AS payments_of_the_load
FROM Enrollment.Payment
WHERE Amount = 1.00 AND PaymentDate = '20261018'
GROUP BY PaymentMethodCode;
GO
-- Step 3. The plan of the evening, forced: for the search of the back office, the plan of
-- the night with the fewest reads per call.
DECLARE @query_id bigint, @plan_id bigint;
SELECT TOP (1) @query_id = p.query_id, @plan_id = p.plan_id
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
GROUP BY p.query_id, p.plan_id
ORDER BY SUM(rs.avg_logical_io_reads * rs.count_executions) / SUM(rs.count_executions);
EXEC sys.sp_query_store_force_plan @query_id = @query_id, @plan_id = @plan_id;
SELECT p.query_id, p.plan_id, p.is_forced_plan, p.force_failure_count
FROM sys.query_store_plan AS p
WHERE p.query_id = @query_id;
GO
-- Step 4. The log, once the transaction is gone and a checkpoint has run.
CHECKPOINT;
SELECT d.log_reuse_wait_desc,
       CAST(l.total_log_size_in_bytes / 1048576.0 AS decimal(10, 1)) AS log_mb,
       CAST(l.used_log_space_in_percent AS decimal(5, 1)) AS used_pct
FROM sys.databases AS d
CROSS JOIN sys.dm_db_log_space_usage AS l
WHERE d.database_id = DB_ID();
GO
