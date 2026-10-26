-- Clips D5.1 and D5.2: one minute of the reports and the enrollment screen, measured. Runs on
-- the throwaway container, in one session, while charge.sh runs. Lasts one minute.
-- ci: skip (it needs the load of charge.sh)
-- The video plays it under the problem, then after each setting of the resource governor.
USE PachadataTraining;
SET NOCOUNT ON;
GO
DECLARE @t0 datetime2(3) = SYSDATETIME();
-- Before: the reports finished so far, the processor time of each pool and group, the waits.
SELECT ISNULL(SUM(execution_count), 0) AS runs INTO #Reports0
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND OBJECT_SCHEMA_NAME(object_id) = N'Report';
SELECT ISNULL(SUM(qs.total_spills), 0) AS spills INTO #Spills0
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE st.dbid = DB_ID() AND OBJECT_SCHEMA_NAME(st.objectid, st.dbid) = N'Report';
SELECT pool_id, total_cpu_usage_ms INTO #Pools0 FROM sys.dm_resource_governor_resource_pools;
SELECT group_id, total_cpu_usage_ms, total_request_count INTO #Groups0
FROM sys.dm_resource_governor_workload_groups;
SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms INTO #Waits0
FROM sys.dm_os_wait_stats
WHERE wait_type IN (N'SOS_SCHEDULER_YIELD', N'RESOURCE_GOVERNOR_IDLE', N'RESOURCE_SEMAPHORE', N'CXPACKET', N'CXCONSUMER');

WAITFOR DELAY '00:01:00';

DECLARE @s decimal(9, 3) = DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0;
-- The enrollment screen during the minute: calls, median, 95th percentile, longest.
SELECT DISTINCT COUNT(*) OVER () AS enrollments,
       CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DurationMs) OVER () AS decimal(9, 1)) AS median_ms,
       CAST(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY DurationMs) OVER () AS decimal(9, 1)) AS p95_ms,
       CAST(MAX(DurationMs) OVER () AS decimal(9, 1)) AS longest_ms
FROM dbo.EntryTiming
WHERE CalledAt >= @t0;
-- The reports finished during the minute, and the pages their sorts spilled to tempdb.
SELECT (SELECT ISNULL(SUM(execution_count), 0) FROM sys.dm_exec_procedure_stats
        WHERE database_id = DB_ID() AND OBJECT_SCHEMA_NAME(object_id) = N'Report')
       - (SELECT runs FROM #Reports0) AS reports_finished,
       (SELECT ISNULL(SUM(qs.total_spills), 0) FROM sys.dm_exec_query_stats AS qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
        WHERE st.dbid = DB_ID() AND OBJECT_SCHEMA_NAME(st.objectid, st.dbid) = N'Report')
       - (SELECT spills FROM #Spills0) AS pages_spilled;
-- Processor time per pool and per group, in processors on average over the minute.
SELECT p.name AS pool,
       CAST((p.total_cpu_usage_ms - p0.total_cpu_usage_ms) / 1000.0 / @s AS decimal(5, 2)) AS processors
FROM sys.dm_resource_governor_resource_pools AS p
JOIN #Pools0 AS p0 ON p0.pool_id = p.pool_id
ORDER BY p.pool_id;
SELECT g.name AS workload_group,
       CAST((g.total_cpu_usage_ms - g0.total_cpu_usage_ms) / 1000.0 / @s AS decimal(5, 2)) AS processors,
       g.total_request_count - g0.total_request_count AS requests
FROM sys.dm_resource_governor_workload_groups AS g
JOIN #Groups0 AS g0 ON g0.group_id = g.group_id
ORDER BY g.group_id;
-- The waits of the minute, all sessions.
SELECT w.wait_type, w.waiting_tasks_count - w0.waiting_tasks_count AS waits,
       CAST((w.wait_time_ms - w0.wait_time_ms) / 1000.0 AS decimal(9, 1)) AS wait_s,
       CAST((w.signal_wait_time_ms - w0.signal_wait_time_ms) / 1000.0 AS decimal(9, 1)) AS signal_s
FROM sys.dm_os_wait_stats AS w
JOIN #Waits0 AS w0 ON w0.wait_type = w.wait_type
ORDER BY w.wait_type;
