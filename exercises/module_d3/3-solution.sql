-- Module D3 exercise: solution. Runs on your lab, in one session (window 2), after
-- 1-start.sql. Start part 1 within five seconds of 2-load.sql in window 1; parts 2 and 3
-- run after the load. Drops ExoWaits at the end. Lasts about a minute and a half.
-- Nothing here changes the instance: the options of part 3 are set on ExoWaits alone.
USE master;
SET NOCOUNT ON;
GO
-- Part 1. The waits of another load, over 30 seconds.
CREATE TABLE #Ignored (wait_type nvarchar(60) PRIMARY KEY);
INSERT #Ignored VALUES
 (N'BROKER_EVENTHANDLER'), (N'BROKER_RECEIVE_WAITFOR'), (N'BROKER_TASK_STOP'),
 (N'BROKER_TO_FLUSH'), (N'BROKER_TRANSMITTER'), (N'CHECKPOINT_QUEUE'), (N'CLR_AUTO_EVENT'),
 (N'CLR_MANUAL_EVENT'), (N'DIRTY_PAGE_POLL'), (N'DISPATCHER_QUEUE_SEMAPHORE'),
 (N'FT_IFTS_SCHEDULER_IDLE_WAIT'), (N'FT_IFTSHC_MUTEX'),
 (N'HADR_FILESTREAM_IOMGR_IOCOMPLETION'), (N'HADR_WORK_QUEUE'), (N'KSOURCE_WAKEUP'),
 (N'LAZYWRITER_SLEEP'), (N'LOGMGR_QUEUE'), (N'ONDEMAND_TASK_QUEUE'),
 (N'PARALLEL_REDO_DRAIN_WORKER'), (N'PARALLEL_REDO_LOG_CACHE'),
 (N'PARALLEL_REDO_TRAN_LIST'), (N'PARALLEL_REDO_WORKER_SYNC'),
 (N'PARALLEL_REDO_WORKER_WAIT_WORK'), (N'PREEMPTIVE_XE_GETTARGETSTATE'),
 (N'PWAIT_ALL_COMPONENTS_INITIALIZED'), (N'PWAIT_DIRECTLOGCONSUMER_GETNEXT'),
 (N'PWAIT_EXTENSIBILITY_CLEANUP_TASK'), (N'QDS_ASYNC_QUEUE'),
 (N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP'), (N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP'),
 (N'QDS_SHUTDOWN_QUEUE'), (N'REDO_THREAD_PENDING_WORK'), (N'REQUEST_FOR_DEADLOCK_SEARCH'),
 (N'RESOURCE_QUEUE'), (N'SERVER_IDLE_CHECK'), (N'SLEEP_BPOOL_FLUSH'), (N'SLEEP_DBSTARTUP'),
 (N'SLEEP_DCOMSTARTUP'), (N'SLEEP_MASTERDBREADY'), (N'SLEEP_MASTERMDREADY'),
 (N'SLEEP_MASTERUPGRADED'), (N'SLEEP_MSDBSTARTUP'), (N'SLEEP_SYSTEMTASK'), (N'SLEEP_TASK'),
 (N'SLEEP_TEMPDBSTARTUP'), (N'SNI_HTTP_ACCEPT'), (N'SOS_WORK_DISPATCHER'),
 (N'SP_SERVER_DIAGNOSTICS_SLEEP'), (N'SQLTRACE_BUFFER_FLUSH'),
 (N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP'), (N'SQLTRACE_WAIT_ENTRIES'), (N'WAIT_FOR_RESULTS'),
 (N'WAITFOR'), (N'WAITFOR_TASKSHUTDOWN'), (N'WAIT_XTP_RECOVERY'), (N'WAIT_XTP_HOST_WAIT'),
 (N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG'), (N'WAIT_XTP_CKPT_CLOSE'), (N'XE_DISPATCHER_JOIN'),
 (N'XE_DISPATCHER_WAIT'), (N'XE_LIVE_TARGET_TVF'), (N'XE_TIMER_EVENT');

SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
INTO #Before
FROM sys.dm_os_wait_stats;

WAITFOR DELAY '00:00:30';

SELECT TOP (8) w.wait_type,
       w.waiting_tasks_count - b.waiting_tasks_count AS waits,
       w.wait_time_ms - b.wait_time_ms AS wait_ms,
       CAST(100.0 * (w.wait_time_ms - b.wait_time_ms)
            / SUM(w.wait_time_ms - b.wait_time_ms) OVER () AS decimal(5, 1)) AS pct,
       CAST(1.0 * (w.wait_time_ms - b.wait_time_ms)
            / NULLIF(w.waiting_tasks_count - b.waiting_tasks_count, 0) AS decimal(10, 3)) AS avg_ms,
       CAST(100.0 * (w.signal_wait_time_ms - b.signal_wait_time_ms)
            / NULLIF(w.wait_time_ms - b.wait_time_ms, 0) AS decimal(5, 1)) AS signal_pct
FROM sys.dm_os_wait_stats AS w
JOIN #Before AS b ON b.wait_type = w.wait_type
WHERE NOT EXISTS (SELECT 1 FROM #Ignored AS i WHERE i.wait_type = w.wait_type)
  AND w.wait_time_ms > b.wait_time_ms
ORDER BY wait_ms DESC;

-- The waits of the session of 2-load.sql, found by the database it works in (no row once it
-- ended). Its text would not do: sql_handle gives the statement as the engine parameterized
-- it, INSERT INTO [dbo].[ClickLog].
SELECT TOP (6) w.session_id, w.wait_type, w.waiting_tasks_count AS waits, w.wait_time_ms AS wait_ms
FROM sys.dm_exec_session_wait_stats AS w
WHERE w.session_id IN (SELECT r.session_id
                       FROM sys.dm_exec_requests AS r
                       WHERE r.session_id <> @@SPID AND r.database_id = DB_ID(N'ExoWaits'))
ORDER BY w.wait_time_ms DESC;
DROP TABLE #Before, #Ignored;
GO

-- Part 2. Batch Requests/sec and SQL Compilations/sec, for a concatenated and a
-- parameterized load. GO 2000 sends the batch before it 2,000 times, as 2,000 batches.
USE PachadataTraining;
GO
CREATE TABLE #Reading (counter_name nvarchar(128), cntr_value bigint, read_at datetime2);
INSERT #Reading
SELECT RTRIM(counter_name), cntr_value, SYSDATETIME()
FROM sys.dm_os_performance_counters
WHERE object_name LIKE N'%:SQL Statistics%'
  AND counter_name IN (N'Batch Requests/sec', N'SQL Compilations/sec');
INSERT #Reading
SELECT N'optimizations', occurrence, SYSDATETIME()
FROM sys.dm_exec_query_optimizer_info
WHERE counter = N'optimizations';
GO
DECLARE @sql nvarchar(400) = N'SELECT s.SessionId, s.StartDate, cl.Title, r.Name AS Room FROM Course.Session AS s JOIN Course.CourseLanguage AS cl ON cl.CourseId = s.CourseId AND cl.LanguageCode = s.LanguageCode LEFT JOIN Reference.TrainingRoom AS r ON r.TrainingRoomId = s.TrainingRoomId WHERE s.SessionId = '
        + CAST(ABS(CHECKSUM(NEWID())) % 19300 + 1 AS nvarchar(10)) + N';';
EXEC (@sql);
GO 2000
-- Load A, per second, and the optimizations in all.
SELECT N'A, concatenated' AS load_name, r.counter_name,
       x.value - r.cntr_value AS during_load,
       CAST((x.value - r.cntr_value) / (DATEDIFF(MILLISECOND, r.read_at, SYSDATETIME()) / 1000.0)
            AS decimal(10, 1)) AS per_second
FROM #Reading AS r
CROSS APPLY (SELECT cntr_value FROM sys.dm_os_performance_counters
             WHERE object_name LIKE N'%:SQL Statistics%' AND RTRIM(counter_name) = r.counter_name
             UNION ALL
             SELECT occurrence FROM sys.dm_exec_query_optimizer_info
             WHERE counter = N'optimizations' AND r.counter_name = N'optimizations') AS x(value);
-- A new starting point for load B.
UPDATE #Reading
SET cntr_value = (SELECT cntr_value FROM sys.dm_os_performance_counters
                  WHERE object_name LIKE N'%:SQL Statistics%' AND RTRIM(counter_name) = #Reading.counter_name),
    read_at = SYSDATETIME()
WHERE counter_name <> N'optimizations';
UPDATE #Reading
SET cntr_value = (SELECT occurrence FROM sys.dm_exec_query_optimizer_info WHERE counter = N'optimizations'),
    read_at = SYSDATETIME()
WHERE counter_name = N'optimizations';
GO
DECLARE @id int = ABS(CHECKSUM(NEWID())) % 19300 + 1;
EXEC sys.sp_executesql
     N'SELECT s.SessionId, s.StartDate, cl.Title, r.Name AS Room FROM Course.Session AS s JOIN Course.CourseLanguage AS cl ON cl.CourseId = s.CourseId AND cl.LanguageCode = s.LanguageCode LEFT JOIN Reference.TrainingRoom AS r ON r.TrainingRoomId = s.TrainingRoomId WHERE s.SessionId = @id;',
     N'@id int', @id = @id;
GO 2000
SELECT N'B, parameterized' AS load_name, r.counter_name,
       x.value - r.cntr_value AS during_load,
       CAST((x.value - r.cntr_value) / (DATEDIFF(MILLISECOND, r.read_at, SYSDATETIME()) / 1000.0)
            AS decimal(10, 1)) AS per_second
FROM #Reading AS r
CROSS APPLY (SELECT cntr_value FROM sys.dm_os_performance_counters
             WHERE object_name LIKE N'%:SQL Statistics%' AND RTRIM(counter_name) = r.counter_name
             UNION ALL
             SELECT occurrence FROM sys.dm_exec_query_optimizer_info
             WHERE counter = N'optimizations' AND r.counter_name = N'optimizations') AS x(value);
-- What each load left in the plan cache.
SELECT cp.objtype, COUNT(*) AS plans, SUM(cp.usecounts) AS uses,
       SUM(CAST(cp.size_in_bytes AS bigint)) / 1024 AS size_kb
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS t
WHERE t.text LIKE N'%FROM Course.Session AS s JOIN Course.CourseLanguage AS cl%'
  AND t.text NOT LIKE N'%dm_exec_cached_plans%'
GROUP BY cp.objtype;
DROP TABLE #Reading;
GO

-- Part 3. The plan cache of one database: OPTIMIZE_FOR_AD_HOC_WORKLOADS and PARAMETERIZATION
-- FORCED set on ExoWaits alone. The same 500 concatenated queries, three times.
USE ExoWaits;
GO
CREATE TABLE #Results (run nvarchar(30), cacheobjtype nvarchar(50), objtype nvarchar(20),
                       plans int, size_kb bigint, used_once int, optimizations bigint);
GO
CREATE PROCEDURE #RunAndCount @run nvarchar(30)
AS
BEGIN
    DECLARE @o0 bigint = (SELECT occurrence FROM sys.dm_exec_query_optimizer_info WHERE counter = N'optimizations');
    DECLARE @i int = 1, @sql nvarchar(400);
    WHILE @i <= 500
    BEGIN
        SET @sql = N'SELECT p.LastName, p.City FROM dbo.Prospect AS p JOIN dbo.Prospect AS q ON q.ProspectId = p.ProspectId + 1 WHERE p.ProspectId = '
                 + CAST(@i * 500 AS nvarchar(10)) + N';';
        EXEC (@sql);
        SET @i += 1;
    END;
    DECLARE @o1 bigint = (SELECT occurrence FROM sys.dm_exec_query_optimizer_info WHERE counter = N'optimizations');
    INSERT #Results
    SELECT @run, cp.cacheobjtype, cp.objtype, COUNT(*),
           SUM(CAST(cp.size_in_bytes AS bigint)) / 1024,
           SUM(CASE WHEN cp.usecounts = 1 THEN 1 ELSE 0 END), @o1 - @o0
    FROM sys.dm_exec_cached_plans AS cp
    CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS t
    WHERE cp.objtype IN (N'Adhoc', N'Prepared')
      AND t.text LIKE N'%LastName%Prospect%ProspectId%'
      AND t.text NOT LIKE N'%dm_exec_cached_plans%'
    GROUP BY cp.cacheobjtype, cp.objtype;
END;
GO
-- Each SET of the option is a batch of its own: set in the batch that runs the loop, it does
-- not apply to that loop (measured on the lab: 500 full plans, as without the option).
-- 1. As delivered.
ALTER DATABASE SCOPED CONFIGURATION SET OPTIMIZE_FOR_AD_HOC_WORKLOADS = OFF;
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
EXEC #RunAndCount N'1. as delivered';
GO
-- 2. With the option of the database: a stub at the first execution of a text.
ALTER DATABASE SCOPED CONFIGURATION SET OPTIMIZE_FOR_AD_HOC_WORKLOADS = ON;
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
EXEC #RunAndCount N'2. ad hoc option';
GO
-- 3. Forced parameterization alone, the option back to OFF (the ALTER DATABASE empties the
-- cache of the database). The prepared plan has the text the engine rewrote, in lower case.
ALTER DATABASE SCOPED CONFIGURATION SET OPTIMIZE_FOR_AD_HOC_WORKLOADS = OFF;
GO
ALTER DATABASE ExoWaits SET PARAMETERIZATION FORCED;
GO
EXEC #RunAndCount N'3. forced parameterization';
GO
SELECT run, cacheobjtype, objtype, plans, size_kb, used_once, optimizations
FROM #Results
ORDER BY run, size_kb DESC;
GO

/*
Answers, measured on the lab of the course (the numbers of each run are in SORTIES.md of the
module, section "Exercice").
Part 1. PREEMPTIVE_OS_FLUSHFILEBUFFERS leads (about 80 % of the time), with as many WRITELOG
  waits: each INSERT commits on its own and waits for its block of journal to be written,
  and on Linux the flush of the file by the system shows as the preemptive wait. LATCH_EX and
  CXSYNC_PORT come from the parallel count of ProspectUS. The session of 2-load.sql shows the
  same waits, in the same proportions: this time the journal waits come from the session
  itself, not from a background task as in the demo. The fix is in the code: group the
  inserts in one transaction.
Part 2. Load A counts about two compilations per batch (the outer batch, then the
  concatenated text) and almost one optimization per batch (fewer when an identifier comes
  back); load B counts one compilation per batch, the outer batch with DECLARE and EXEC, and
  three optimizations in all: the plan of the parameterized query is reused. A is left as
  about 1,900 ad hoc plans (some 220 MB), B as one prepared plan of 120 KB used 2,000 times.
  An application that calls sp_executesql through its client library (RPC) does not send
  the outer batch.
Part 3. As delivered, 500 full ad hoc plans used once (36 MB) and 500 optimizations; with the
  option, 500 stubs (222 KB) and the same 500 optimizations; with forced parameterization,
  one prepared plan, one optimization, and 500 ad hoc entries of 16 KB that point to it. The
  option of the database reduces the memory and keeps the optimizations; forced
  parameterization reduces both. The option of the database is tried on one database, while
  optimize for ad hoc workloads changes the whole instance.
*/

-- Cleanup: the exercise database, and its plans with it.
USE master;
GO
DROP DATABASE IF EXISTS ExoWaits;
GO
