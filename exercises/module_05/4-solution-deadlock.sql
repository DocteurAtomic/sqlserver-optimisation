-- ci: skip (reads the deadlock that 3a-window-1.sql and 3b-window-2.sql produced)
-- Module 5 exercise, part 2: solution. Runs on the lab, in a third window, after the two
-- windows. The file of system_health can be two minutes late (its MAX_DISPATCH_LATENCY):
-- if nothing comes back, wait and run it again.
USE master;
GO
SET NOCOUNT ON;
GO
-- 1. The deadlocks of the last 30 minutes on a key of Enrollment.Payment, one row per
--    process. For a batch sent by a client, the execution stack gives the line of the
--    statement in the batch (its text may only say "unknown"; the whole batch is in
--    inputbuf).
WITH reports AS (
    SELECT timestamp_utc, CAST(event_data AS xml).query('event/data/value/deadlock') AS graph
    FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
    WHERE object_name = N'xml_deadlock_report'
      AND timestamp_utc > DATEADD(MINUTE, -30, SYSUTCDATETIME())
)
SELECT r.timestamp_utc,
       p.n.value('@spid', 'int') AS spid,
       CASE WHEN p.n.value('@id', 'varchar(50)')
                 = r.graph.value('(deadlock/victim-list/victimProcess/@id)[1]', 'varchar(50)')
            THEN 'victim' ELSE '' END AS role,
       p.n.value('@lockMode', 'varchar(10)') AS lock_wanted,
       p.n.value('@waitresource', 'varchar(60)') AS wait_resource,
       p.n.value('@logused', 'int') AS log_used,
       p.n.value('(executionStack/frame/@line)[1]', 'int') AS line_in_batch
FROM reports AS r
CROSS APPLY r.graph.nodes('deadlock/process-list/process') AS p(n)
WHERE r.graph.exist('//keylock[@objectname = "PachadataTraining.Enrollment.Payment"]') = 1
ORDER BY r.timestamp_utc DESC, role DESC;

-- 2. The resources of the last one: which index, held by whom, wanted by whom.
WITH last_report AS (
    SELECT TOP (1) CAST(event_data AS xml).query('event/data/value/deadlock') AS graph
    FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
    WHERE object_name = N'xml_deadlock_report'
      AND timestamp_utc > DATEADD(MINUTE, -30, SYSUTCDATETIME())
      AND CAST(event_data AS xml).exist('//keylock[@objectname = "PachadataTraining.Enrollment.Payment"]') = 1
    ORDER BY timestamp_utc DESC
)
SELECT r.n.value('@objectname', 'nvarchar(200)') AS object_name,
       r.n.value('@indexname', 'nvarchar(200)') AS index_name,
       r.n.value('(owner-list/owner/@mode)[1]', 'varchar(10)') AS held_mode,
       ho.n.value('@spid', 'int') AS held_by_spid,
       r.n.value('(waiter-list/waiter/@mode)[1]', 'varchar(10)') AS wanted_mode,
       wo.n.value('@spid', 'int') AS wanted_by_spid
FROM last_report
CROSS APPLY last_report.graph.nodes('deadlock/resource-list/keylock') AS r(n)
CROSS APPLY last_report.graph.nodes('deadlock/process-list/process') AS ho(n)
CROSS APPLY last_report.graph.nodes('deadlock/process-list/process') AS wo(n)
WHERE ho.n.value('@id', 'varchar(50)') = r.n.value('(owner-list/owner/@id)[1]', 'varchar(50)')
  AND wo.n.value('@id', 'varchar(50)') = r.n.value('(waiter-list/waiter/@id)[1]', 'varchar(50)');
GO
-- 3. The fix: both transactions take the tables in the same order. Run 3a-window-1.sql
--    again unchanged in window 1, and this one in window 2 within five seconds: the
--    payment first, then the invoice.
--
--    USE PachadataTraining;
--    BEGIN TRANSACTION;
--    UPDATE Enrollment.Payment SET CheckNumber = '2477912' WHERE PaymentId = 106875;
--    WAITFOR DELAY '00:00:05';
--    UPDATE Enrollment.Invoice SET ReminderLevel = 2, ReminderDate = '20261026'
--    WHERE InvoiceCode = 'FA2026-006089';
--    COMMIT;
--
--    Window 2 waits for window 1 to commit, then goes through: a blocking, no deadlock.
--    Two minutes later, the count below has not changed.
SELECT COUNT(*) AS payment_deadlocks_last_30_minutes
FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
WHERE object_name = N'xml_deadlock_report'
  AND timestamp_utc > DATEADD(MINUTE, -30, SYSUTCDATETIME())
  AND CAST(event_data AS xml).exist('//keylock[@objectname = "PachadataTraining.Enrollment.Payment"]') = 1;
GO
