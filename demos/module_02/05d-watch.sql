-- ci: skip (three sessions: run while 05c-blocked-update.sql waits)
-- Clip 2.3, session 3: what SQLOS shows of the waiting session. The UPDATE of session 2 is
-- found as the request of this database that waits for a lock; in SSMS, you can filter on
-- its session_id instead.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- The request: its state, what it waits for, for how long, and the processor time it used.
SELECT r.session_id, r.status, r.wait_type, r.wait_time AS wait_ms,
       r.blocking_session_id, r.cpu_time AS cpu_ms, r.total_elapsed_time AS elapsed_ms
FROM sys.dm_exec_requests AS r
WHERE r.database_id = DB_ID() AND r.session_id <> @@SPID AND r.wait_type LIKE N'LCK%'
  AND r.session_id IN (SELECT session_id FROM sys.dm_exec_sessions WHERE is_user_process = 1);

-- Its task, the worker that runs it, and the scheduler that worker belongs to.
SELECT k.session_id, k.task_state, k.scheduler_id, w.state AS worker_state,
       s.current_tasks_count, s.runnable_tasks_count
FROM sys.dm_exec_requests AS r
JOIN sys.dm_os_tasks AS k ON k.task_address = r.task_address
JOIN sys.dm_os_workers AS w ON w.worker_address = k.worker_address
JOIN sys.dm_os_schedulers AS s ON s.scheduler_id = k.scheduler_id
WHERE r.database_id = DB_ID() AND r.session_id <> @@SPID AND r.wait_type LIKE N'LCK%'
  AND r.session_id IN (SELECT session_id FROM sys.dm_exec_sessions WHERE is_user_process = 1);

-- The waiting task, and the resource it waits for.
SELECT wt.session_id, wt.wait_type, wt.wait_duration_ms, wt.blocking_session_id,
       wt.resource_description
FROM sys.dm_os_waiting_tasks AS wt
WHERE wt.wait_type LIKE N'LCK%' AND wt.session_id <> @@SPID
  AND wt.session_id IN (SELECT session_id FROM sys.dm_exec_sessions WHERE is_user_process = 1);
GO
-- The same request ten seconds later: the wait has grown, the processor time has not.
WAITFOR DELAY '00:00:10';
SELECT r.session_id, r.status, r.wait_type, r.wait_time AS wait_ms, r.cpu_time AS cpu_ms,
       r.total_elapsed_time AS elapsed_ms
FROM sys.dm_exec_requests AS r
WHERE r.database_id = DB_ID() AND r.session_id <> @@SPID AND r.wait_type LIKE N'LCK%'
  AND r.session_id IN (SELECT session_id FROM sys.dm_exec_sessions WHERE is_user_process = 1);
