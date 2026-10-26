-- Clip 2.2: what a commit costs in log writes, and what the checkpoint writes afterwards.
-- Runs on the lab, in one session. Demo.FlagReminders_Slow updates one invoice at a time,
-- each UPDATE being its own transaction. The script keeps the reminder columns before the
-- first run and puts them back between the two runs, so that both runs flag the same invoices.
USE PachadataTraining;
SET NOCOUNT ON;
GO
SELECT InvoiceCode, ReminderLevel, ReminderDate
INTO #Saved
FROM Enrollment.Invoice;

CREATE TABLE #Runs (Run varchar(30), elapsed_ms int, log_writes bigint, log_kb bigint,
                    writelog_waits bigint, flush_waits bigint, flush_ms bigint);
GO
-- Run 1: the loop as written, one transaction per invoice (autocommit).
DECLARE @t datetime2 = SYSDATETIME(),
        @writes bigint, @bytes bigint, @wl bigint, @fl bigint, @flms bigint;
SELECT @writes = num_of_writes, @bytes = num_of_bytes_written
FROM sys.dm_io_virtual_file_stats(DB_ID(), 2);          -- file 2: the log
SELECT @wl = ISNULL(SUM(CASE WHEN wait_type = N'WRITELOG' THEN waiting_tasks_count ELSE 0 END), 0),
       @fl = ISNULL(SUM(CASE WHEN wait_type = N'PREEMPTIVE_OS_FLUSHFILEBUFFERS' THEN waiting_tasks_count ELSE 0 END), 0),
       @flms = ISNULL(SUM(CASE WHEN wait_type = N'PREEMPTIVE_OS_FLUSHFILEBUFFERS' THEN wait_time_ms ELSE 0 END), 0)
FROM sys.dm_exec_session_wait_stats WHERE session_id = @@SPID;

EXEC Demo.FlagReminders_Slow @AsOfDate = '20261231';

INSERT #Runs
SELECT 'one transaction per invoice', DATEDIFF(ms, @t, SYSDATETIME()),
       f.num_of_writes - @writes, (f.num_of_bytes_written - @bytes) / 1024,
       w.wl - @wl, w.fl - @fl, w.flms - @flms
FROM sys.dm_io_virtual_file_stats(DB_ID(), 2) AS f
CROSS JOIN (SELECT ISNULL(SUM(CASE WHEN wait_type = N'WRITELOG' THEN waiting_tasks_count ELSE 0 END), 0) AS wl,
                   ISNULL(SUM(CASE WHEN wait_type = N'PREEMPTIVE_OS_FLUSHFILEBUFFERS' THEN waiting_tasks_count ELSE 0 END), 0) AS fl,
                   ISNULL(SUM(CASE WHEN wait_type = N'PREEMPTIVE_OS_FLUSHFILEBUFFERS' THEN wait_time_ms ELSE 0 END), 0) AS flms
            FROM sys.dm_exec_session_wait_stats WHERE session_id = @@SPID) AS w;
GO
-- Back to the state before run 1.
UPDATE i
SET ReminderLevel = s.ReminderLevel, ReminderDate = s.ReminderDate
FROM Enrollment.Invoice AS i
JOIN #Saved AS s ON s.InvoiceCode = i.InvoiceCode
WHERE i.ReminderDate = '20261231';
CHECKPOINT;
GO
-- Run 2: the same loop inside one explicit transaction, one commit at the end.
DECLARE @t datetime2 = SYSDATETIME(),
        @writes bigint, @bytes bigint, @wl bigint, @fl bigint, @flms bigint;
SELECT @writes = num_of_writes, @bytes = num_of_bytes_written
FROM sys.dm_io_virtual_file_stats(DB_ID(), 2);
SELECT @wl = ISNULL(SUM(CASE WHEN wait_type = N'WRITELOG' THEN waiting_tasks_count ELSE 0 END), 0),
       @fl = ISNULL(SUM(CASE WHEN wait_type = N'PREEMPTIVE_OS_FLUSHFILEBUFFERS' THEN waiting_tasks_count ELSE 0 END), 0),
       @flms = ISNULL(SUM(CASE WHEN wait_type = N'PREEMPTIVE_OS_FLUSHFILEBUFFERS' THEN wait_time_ms ELSE 0 END), 0)
FROM sys.dm_exec_session_wait_stats WHERE session_id = @@SPID;

BEGIN TRANSACTION;
EXEC Demo.FlagReminders_Slow @AsOfDate = '20261231';
COMMIT;

INSERT #Runs
SELECT 'one transaction for all', DATEDIFF(ms, @t, SYSDATETIME()),
       f.num_of_writes - @writes, (f.num_of_bytes_written - @bytes) / 1024,
       w.wl - @wl, w.fl - @fl, w.flms - @flms
FROM sys.dm_io_virtual_file_stats(DB_ID(), 2) AS f
CROSS JOIN (SELECT ISNULL(SUM(CASE WHEN wait_type = N'WRITELOG' THEN waiting_tasks_count ELSE 0 END), 0) AS wl,
                   ISNULL(SUM(CASE WHEN wait_type = N'PREEMPTIVE_OS_FLUSHFILEBUFFERS' THEN waiting_tasks_count ELSE 0 END), 0) AS fl,
                   ISNULL(SUM(CASE WHEN wait_type = N'PREEMPTIVE_OS_FLUSHFILEBUFFERS' THEN wait_time_ms ELSE 0 END), 0) AS flms
            FROM sys.dm_exec_session_wait_stats WHERE session_id = @@SPID) AS w;

SELECT Run, elapsed_ms, log_writes, log_kb, writelog_waits, flush_waits, flush_ms FROM #Runs;
GO
-- The data pages changed by the run are in the cache, marked dirty: not yet on disk.
SELECT COUNT(*) AS DirtyPages
FROM sys.dm_os_buffer_descriptors
WHERE database_id = DB_ID() AND is_modified = 1;

-- The checkpoint writes them to the data file.
DECLARE @dw bigint = (SELECT num_of_writes FROM sys.dm_io_virtual_file_stats(DB_ID(), 1));
CHECKPOINT;
SELECT (SELECT COUNT(*) FROM sys.dm_os_buffer_descriptors
        WHERE database_id = DB_ID() AND is_modified = 1) AS DirtyPagesAfter,
       (SELECT num_of_writes FROM sys.dm_io_virtual_file_stats(DB_ID(), 1)) - @dw AS DataFileWrites;
GO
-- This database still uses the automatic checkpoint of SQL Server 2008: target 0.
SELECT name, recovery_model_desc, target_recovery_time_in_seconds
FROM sys.databases
WHERE name IN (N'model', N'PachadataTraining');
