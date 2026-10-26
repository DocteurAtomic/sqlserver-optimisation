-- Clip D1.3 (and D1.4, after the fix): the dashboard queries under load.
-- ci: skip (it needs the load: ./demos/module_d1/charge.sh dashboard, started before)
-- Runs on the lab, in one session, while charge.sh runs; it lasts a little over a minute.
USE PachadataTraining;
SET NOCOUNT ON;
GO
SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
INTO #Waits
FROM sys.dm_os_wait_stats;
SELECT sql_handle, plan_handle, statement_start_offset, execution_count,
       total_worker_time, total_elapsed_time
INTO #Queries
FROM sys.dm_exec_query_stats;

WAITFOR DELAY '00:01:00';

-- The waits of the minute. signal_ms is the time spent in the runnable queue, waiting for
-- a processor once the resource was there.
SELECT TOP (6) w.wait_type,
       w.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) AS waits,
       w.wait_time_ms - ISNULL(b.wait_time_ms, 0) AS wait_ms,
       w.signal_wait_time_ms - ISNULL(b.signal_wait_time_ms, 0) AS signal_ms
FROM sys.dm_os_wait_stats AS w
LEFT JOIN #Waits AS b ON b.wait_type = w.wait_type
WHERE w.wait_type IN (N'SOS_SCHEDULER_YIELD', N'CXPACKET', N'CXCONSUMER', N'CXSYNC_PORT',
                      N'CXSYNC_CONSUMER', N'LATCH_EX', N'THREADPOOL', N'RESOURCE_SEMAPHORE',
                      N'PAGEIOLATCH_SH')
  AND w.wait_time_ms - ISNULL(b.wait_time_ms, 0) > 0
ORDER BY wait_ms DESC;

-- The dashboard query in that minute: executions, and the time per execution.
SELECT SUM(s.execution_count - ISNULL(b.execution_count, 0)) AS executions,
       SUM(s.total_worker_time - ISNULL(b.total_worker_time, 0)) / 1000
         / NULLIF(SUM(s.execution_count - ISNULL(b.execution_count, 0)), 0) AS cpu_ms_per_exec,
       SUM(s.total_elapsed_time - ISNULL(b.total_elapsed_time, 0)) / 1000
         / NULLIF(SUM(s.execution_count - ISNULL(b.execution_count, 0)), 0) AS elapsed_ms_per_exec,
       MAX(s.last_dop) AS last_dop
FROM sys.dm_exec_query_stats AS s
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
LEFT JOIN #Queries AS b
  ON b.sql_handle = s.sql_handle AND b.plan_handle = s.plan_handle
 AND b.statement_start_offset = s.statement_start_offset
WHERE t.text LIKE N'%FROM Enrollment.InvoiceLine WHERE Label LIKE @pattern%'
  AND t.text NOT LIKE N'%dm_exec_query_stats%';

-- The schedulers right now: workers, and tasks that wait for a processor.
SELECT COUNT(*) AS schedulers, SUM(current_workers_count) AS workers,
       SUM(active_workers_count) AS active_workers, SUM(runnable_tasks_count) AS runnable_tasks
FROM sys.dm_os_schedulers
WHERE status = N'VISIBLE ONLINE';
