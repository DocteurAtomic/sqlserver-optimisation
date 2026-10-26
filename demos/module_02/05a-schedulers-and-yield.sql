-- Clip 2.3: the schedulers that SQLOS sees, then a query that only needs the processor.
-- Runs on the lab, in one session.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- One scheduler per logical processor that the engine sees. In the lab container, the
-- engine sees the processors of the host, not the quota of the container.
SELECT status, COUNT(*) AS schedulers,
       SUM(current_tasks_count) AS current_tasks,
       SUM(runnable_tasks_count) AS runnable_tasks,
       SUM(current_workers_count) AS workers
FROM sys.dm_os_schedulers
GROUP BY status
ORDER BY status;

SELECT cpu_count, scheduler_count, max_workers_count
FROM sys.dm_os_sys_info;
GO
-- A scan whose pages are all in the cache, on one thread (MAXDOP 1, a query hint seen in
-- clip 2.4). The first run warms the cache, the second one is measured.
SELECT COUNT(*) AS Events FROM Elearning.Activity WHERE EventTime >= '20260101' AND EventTime < '20260401' OPTION (MAXDOP 1);
GO
SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
INTO #WaitsBefore
FROM sys.dm_exec_session_wait_stats
WHERE session_id = @@SPID;

DECLARE @t datetime2 = SYSDATETIME(),
        @cpu int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID);

SELECT COUNT(*) AS Events, SUM(CAST(DurationSeconds AS bigint)) AS Seconds
FROM Elearning.Activity
WHERE EventTime >= '20260101' AND EventTime < '20260401'
OPTION (MAXDOP 1);

SELECT DATEDIFF(ms, @t, SYSDATETIME()) AS elapsed_ms,
       (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID) - @cpu AS cpu_ms;

-- Its waits: SOS_SCHEDULER_YIELD is the task leaving the processor at the end of its
-- quantum, then waiting in the runnable queue (signal wait) for its turn.
SELECT w.wait_type,
       w.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) AS waits,
       w.wait_time_ms - ISNULL(b.wait_time_ms, 0) AS wait_ms,
       w.signal_wait_time_ms - ISNULL(b.signal_wait_time_ms, 0) AS signal_ms
FROM sys.dm_exec_session_wait_stats AS w
LEFT JOIN #WaitsBefore AS b ON b.wait_type = w.wait_type
WHERE w.session_id = @@SPID
  AND w.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) > 0
ORDER BY wait_ms DESC;
