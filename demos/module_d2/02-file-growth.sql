-- Clip D2.2: the growths of the files. Runs on the lab, in one session, after
-- 01-io-interval.sql. Part 3 grows the data file by hand, by its 10 %.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. How the files are set to grow.
SELECT name, type_desc, size / 128 AS size_mb,
       CASE WHEN is_percent_growth = 1 THEN CONCAT(growth, ' %')
            ELSE CONCAT(growth / 128, ' MB') END AS growth
FROM sys.database_files;
GO
-- 2. What the default trace recorded since the database was restored: one event per
--    automatic growth (event 92 for a data file, 93 for a log file), with the pages added
--    (IntegerData, in 8 KB pages) and the duration (in microseconds). The trace rolls over
--    files of 20 MB: reading from log.trc, without the number, reads all those still kept.
DECLARE @trace nvarchar(260) = (
    SELECT CASE WHEN path LIKE N'%log[_]%.trc'
                THEN LEFT(path, LEN(path) - CHARINDEX(N'_', REVERSE(path))) + N'.trc'
                ELSE path END
    FROM sys.traces WHERE is_default = 1);
DECLARE @restored datetime = (SELECT MAX(restore_date) FROM msdb.dbo.restorehistory
                              WHERE destination_database_name = DB_NAME());
SELECT te.name AS event_name,
       COUNT(*) AS growths,
       SUM(t.IntegerData) / 128 AS added_mb,
       SUM(t.Duration) / 1000 AS total_ms,
       CAST(AVG(t.Duration) / 1000.0 AS decimal(10, 1)) AS avg_ms,
       MAX(t.Duration) / 1000 AS max_ms
FROM sys.fn_trace_gettable(@trace, DEFAULT) AS t
JOIN sys.trace_events AS te ON te.trace_event_id = t.EventClass
WHERE t.EventClass IN (92, 93)
  AND t.DatabaseName = DB_NAME()
  AND t.StartTime >= @restored
GROUP BY te.name;
GO
-- 3. Instant file initialization: is it on for the engine?
SELECT servicename, instant_file_initialization_enabled
FROM sys.dm_server_services;
GO
-- 4. One growth of 10 % of the data file, by hand, with the waits of the session.
DROP TABLE IF EXISTS #waits_before;
SELECT wait_type, waiting_tasks_count, wait_time_ms
INTO #waits_before
FROM sys.dm_exec_session_wait_stats
WHERE session_id = @@SPID;
DECLARE @size_mb int = (SELECT size / 128 FROM sys.database_files WHERE file_id = 1);
DECLARE @new_mb int = @size_mb + @size_mb / 10;
DECLARE @sql nvarchar(300) = N'ALTER DATABASE ' + QUOTENAME(DB_NAME())
    + N' MODIFY FILE (NAME = PachadataTraining, SIZE = ' + CAST(@new_mb AS nvarchar(10)) + N'MB);';
DECLARE @start datetime2 = SYSDATETIME();
EXEC (@sql);
SELECT @size_mb AS before_mb, @new_mb AS after_mb,
       DATEDIFF(MILLISECOND, @start, SYSDATETIME()) AS growth_ms;
SELECT w.wait_type,
       w.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) AS waits,
       w.wait_time_ms - ISNULL(b.wait_time_ms, 0) AS wait_ms
FROM sys.dm_exec_session_wait_stats AS w
LEFT JOIN #waits_before AS b ON b.wait_type = w.wait_type
WHERE w.session_id = @@SPID
  AND w.wait_type LIKE N'PREEMPTIVE_OS_%'
  AND w.waiting_tasks_count > ISNULL(b.waiting_tasks_count, 0)
ORDER BY wait_ms DESC;
GO
