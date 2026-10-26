-- Clips D4.2 to D4.4: one minute of the portal, measured. Runs on the lab, in one session,
-- while charge.sh runs (alone, it returns zero calls). Lasts one minute. The video plays it
-- three times: under the problem, with the memory-optimized metadata, and after the fix.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- Before: the calls of the procedure, the temporary tables created, the page latch waits.
DECLARE @t0 datetime2 = SYSDATETIME();
SELECT ISNULL(SUM(execution_count), 0) AS calls, ISNULL(SUM(total_elapsed_time), 0) AS elapsed_us
INTO #Proc0
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Course.GetAttendanceSheet');
SELECT cntr_value INTO #Created0
FROM sys.dm_os_performance_counters
WHERE RTRIM(object_name) LIKE N'%:General Statistics'
  AND RTRIM(counter_name) = N'Temp Tables Creation Rate';
SELECT wait_type, waiting_tasks_count, wait_time_ms INTO #Waits0
FROM sys.dm_os_wait_stats
WHERE wait_type IN (N'PAGELATCH_EX', N'PAGELATCH_SH', N'PAGELATCH_UP');

WAITFOR DELAY '00:01:00';

DECLARE @s decimal(9, 3) = DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0;
-- After: rates per second, and the average duration of a call.
SELECT CAST((p.calls - p0.calls) / @s AS decimal(9, 0)) AS calls_per_s,
       CAST((p.elapsed_us - p0.elapsed_us) / 1000.0 / NULLIF(p.calls - p0.calls, 0) AS decimal(9, 1)) AS avg_call_ms,
       CAST((c.cntr_value - c0.cntr_value) / @s AS decimal(9, 0)) AS temp_tables_created_per_s
FROM (SELECT ISNULL(SUM(execution_count), 0) AS calls, ISNULL(SUM(total_elapsed_time), 0) AS elapsed_us
      FROM sys.dm_exec_procedure_stats
      WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Course.GetAttendanceSheet')) AS p
CROSS JOIN #Proc0 AS p0
CROSS JOIN (SELECT cntr_value FROM sys.dm_os_performance_counters
            WHERE RTRIM(object_name) LIKE N'%:General Statistics'
              AND RTRIM(counter_name) = N'Temp Tables Creation Rate') AS c
CROSS JOIN #Created0 AS c0;

-- The page latch waits of the minute, all databases: tasks and seconds of waiting.
SELECT w.wait_type, w.waiting_tasks_count - w0.waiting_tasks_count AS waits,
       CAST((w.wait_time_ms - w0.wait_time_ms) / 1000.0 AS decimal(9, 1)) AS wait_s
FROM sys.dm_os_wait_stats AS w
JOIN #Waits0 AS w0 ON w0.wait_type = w.wait_type
ORDER BY w.wait_type;

-- The state of the instance: the option of clip D4.3, the files of tempdb, and the memory
-- of In-Memory OLTP (the memory-optimized metadata of tempdb is counted there).
SELECT SERVERPROPERTY('IsTempdbMetadataMemoryOptimized') AS memory_optimized_metadata,
       (SELECT COUNT(*) FROM tempdb.sys.database_files WHERE type_desc = N'ROWS') AS tempdb_data_files,
       (SELECT SUM(pages_kb) / 1024 FROM sys.dm_os_memory_clerks WHERE type = N'MEMORYCLERK_XTP') AS xtp_clerk_mb;
