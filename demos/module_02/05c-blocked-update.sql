-- ci: skip (three sessions: run 05b-hold-a-lock.sql first, in another window)
-- Clip 2.3, session 2: the accountant raises the reminder level of the same invoice. The
-- UPDATE waits for the lock of session 1; at the end, the session tells what it waited for.
USE PachadataTraining;
SET NOCOUNT ON;
DECLARE @t datetime2 = SYSDATETIME();
SELECT @@SPID AS SessionId;

UPDATE Enrollment.Invoice
SET ReminderLevel = ReminderLevel + 1, ReminderDate = '20261026'
WHERE InvoiceCode = 'FA2026-007500';

SELECT DATEDIFF(ms, @t, SYSDATETIME()) AS elapsed_ms,
       (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID) AS cpu_ms_of_batch;

SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
FROM sys.dm_exec_session_wait_stats
WHERE session_id = @@SPID AND wait_type LIKE N'LCK%';

-- Undo the change, so that the script can be replayed.
UPDATE Enrollment.Invoice
SET ReminderLevel = ReminderLevel - 1, ReminderDate = NULL
WHERE InvoiceCode = 'FA2026-007500';
