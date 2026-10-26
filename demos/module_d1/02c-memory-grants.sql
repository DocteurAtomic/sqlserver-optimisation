-- Clip D1.2 (and D1.4, after the fix): the memory grants of the reports under load.
-- ci: skip (it needs the load: ./demos/module_d1/charge.sh reports, started before)
-- Runs on the lab, in one session, while charge.sh runs; it lasts a little over a minute.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- The grants right now: a NULL granted_mb is a query that waits for its memory.
SELECT session_id, dop, requested_memory_kb / 1024 AS requested_mb,
       granted_memory_kb / 1024 AS granted_mb, used_memory_kb / 1024 AS used_mb, wait_time_ms
FROM sys.dm_exec_query_memory_grants
WHERE session_id <> @@SPID
ORDER BY session_id;

SELECT target_memory_kb / 1024 AS target_mb, available_memory_kb / 1024 AS available_mb,
       granted_memory_kb / 1024 AS granted_mb, grantee_count, waiter_count
FROM sys.dm_exec_query_resource_semaphores
WHERE pool_id = 2 AND resource_semaphore_id = 0;
GO
-- One minute of the load: the waits of the instance and the executions of the report,
-- read before and after.
SELECT wait_type, waiting_tasks_count, wait_time_ms
INTO #Waits
FROM sys.dm_os_wait_stats;
SELECT sql_handle, plan_handle, statement_start_offset, execution_count, total_spills
INTO #Queries
FROM sys.dm_exec_query_stats;

WAITFOR DELAY '00:01:00';

SELECT TOP (6) w.wait_type,
       w.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) AS waits,
       w.wait_time_ms - ISNULL(b.wait_time_ms, 0) AS wait_ms
FROM sys.dm_os_wait_stats AS w
LEFT JOIN #Waits AS b ON b.wait_type = w.wait_type
WHERE w.wait_type IN (N'RESOURCE_SEMAPHORE', N'SOS_SCHEDULER_YIELD', N'CXPACKET',
                      N'CXCONSUMER', N'CXSYNC_PORT', N'CXSYNC_CONSUMER', N'LATCH_EX',
                      N'BPSORT', N'PAGEIOLATCH_SH', N'IO_COMPLETION')
  AND w.wait_time_ms - ISNULL(b.wait_time_ms, 0) > 0
ORDER BY wait_ms DESC;

-- Report.ActivityByDevice in that minute: executions, spills, and its last grant.
SELECT SUM(s.execution_count - ISNULL(b.execution_count, 0)) AS executions,
       SUM(s.total_spills - ISNULL(b.total_spills, 0)) AS spills,
       MAX(s.last_dop) AS last_dop,
       MAX(s.last_grant_kb) / 1024 AS last_grant_mb,
       MAX(s.last_used_grant_kb) / 1024 AS last_used_grant_mb
FROM sys.dm_exec_query_stats AS s
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
LEFT JOIN #Queries AS b
  ON b.sql_handle = s.sql_handle AND b.plan_handle = s.plan_handle
 AND b.statement_start_offset = s.statement_start_offset
WHERE t.objectid = OBJECT_ID(N'Report.ActivityByDevice')
  AND t.dbid = DB_ID();

-- The memory clerks after a minute of reports.
SELECT TOP (4) type, SUM(pages_kb) / 1024 AS mb
FROM sys.dm_os_memory_clerks
GROUP BY type
ORDER BY mb DESC;
