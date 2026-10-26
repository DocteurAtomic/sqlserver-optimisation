-- Clip D3.1: the waits of the instance over one minute. Runs on the lab, in one session,
-- while charge.sh runs (it also runs alone: the waits are then those of an idle lab).
-- Lasts one minute.
USE master;
SET NOCOUNT ON;
GO
-- The idle waits: system tasks that sleep until they have work (lazy writer, checkpoint,
-- deadlock monitor, Extended Events, Service Broker, Query Store loops...). They grow on an
-- instance that does nothing, and say nothing about the load.
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

-- 1. First snapshot, one minute, second snapshot.
SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
INTO #Before
FROM sys.dm_os_wait_stats;

WAITFOR DELAY '00:01:00';

SELECT w.wait_type,
       w.waiting_tasks_count - b.waiting_tasks_count AS waits,
       w.wait_time_ms - b.wait_time_ms AS wait_ms,
       w.signal_wait_time_ms - b.signal_wait_time_ms AS signal_ms
INTO #Interval
FROM sys.dm_os_wait_stats AS w
JOIN #Before AS b ON b.wait_type = w.wait_type
WHERE NOT EXISTS (SELECT 1 FROM #Ignored AS i WHERE i.wait_type = w.wait_type)
  AND w.wait_time_ms > b.wait_time_ms;

-- 2. The waits of the minute: share of the total, average wait, share spent waiting for a
--    processor once the resource was there (signal).
SELECT TOP (8) wait_type, waits, wait_ms,
       CAST(100.0 * wait_ms / SUM(wait_ms) OVER () AS decimal(5, 1)) AS pct,
       CAST(1.0 * wait_ms / NULLIF(waits, 0) AS decimal(10, 3)) AS avg_ms,
       CAST(100.0 * signal_ms / NULLIF(wait_ms, 0) AS decimal(5, 1)) AS signal_pct
FROM #Interval
ORDER BY wait_ms DESC;

-- 3. Signal and resource, over all the waits of the minute.
SELECT SUM(wait_ms) / 1000 AS wait_s,
       SUM(signal_ms) / 1000 AS signal_s,
       CAST(100.0 * SUM(signal_ms) / NULLIF(SUM(wait_ms), 0) AS decimal(5, 1)) AS signal_pct
FROM #Interval;

-- 4. The schedulers right now: tasks that have everything they need but a processor.
SELECT COUNT(*) AS schedulers, SUM(current_tasks_count) AS tasks,
       SUM(runnable_tasks_count) AS runnable_tasks
FROM sys.dm_os_schedulers
WHERE status = N'VISIBLE ONLINE';
