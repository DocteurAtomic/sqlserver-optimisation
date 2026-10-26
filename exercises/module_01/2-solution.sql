-- Module 1 exercise, solution. Run it in window 2 while window 1 runs 1-start.sql
-- (alone, the queries on the running request return no row). Reads only; creates nothing.
USE master;
GO
-- 1. The instance: what the engine sees of the lab. cpu_count and scheduler_count give the
--    processors of the host, not the 4 of the container limit; physical_memory_mb is
--    80 % of the 6 GB limit.
SELECT cpu_count, scheduler_count,
       physical_memory_kb / 1024 AS physical_memory_mb,
       committed_target_kb / 1024 AS target_memory_mb,
       max_workers_count, container_type_desc, sqlserver_start_time
FROM sys.dm_os_sys_info;
GO
-- 2. The request of window 1: state, wait, consumption, degree of parallelism, statement.
SELECT r.session_id, r.status, r.command, r.wait_type, r.last_wait_type,
       r.cpu_time AS cpu_ms, r.total_elapsed_time AS elapsed_ms,
       r.logical_reads, r.granted_query_memory * 8 AS granted_memory_kb, r.dop,
       SUBSTRING(t.text, r.statement_start_offset / 2 + 1,
                 (CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
                       ELSE r.statement_end_offset END - r.statement_start_offset) / 2 + 1)
           AS statement_text
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE s.is_user_process = 1
  AND r.session_id <> @@SPID;
-- 3. Its tasks: one per thread of the parallel plan, each with its own wait.
SELECT wt.session_id, wt.exec_context_id, wt.wait_type, wt.wait_duration_ms
FROM sys.dm_os_waiting_tasks AS wt
JOIN sys.dm_exec_sessions AS s ON s.session_id = wt.session_id
WHERE s.is_user_process = 1
  AND wt.session_id <> @@SPID
ORDER BY wt.session_id, wt.exec_context_id;
-- 4. Its progress, operator by operator (lightweight profiling, on by default since 2019):
--    rows produced so far against rows estimated, summed over the threads.
SELECT qp.session_id, qp.node_id, qp.physical_operator_name,
       SUM(qp.row_count) AS rows_so_far, MAX(qp.estimate_row_count) AS rows_estimated
FROM sys.dm_exec_query_profiles AS qp
WHERE qp.session_id <> @@SPID
GROUP BY qp.session_id, qp.node_id, qp.physical_operator_name
ORDER BY qp.session_id, qp.node_id;
-- 5. What the session has waited for since it opened, by type.
SELECT w.session_id, w.wait_type, w.waiting_tasks_count, w.wait_time_ms, w.signal_wait_time_ms
FROM sys.dm_exec_session_wait_stats AS w
JOIN sys.dm_exec_requests AS r ON r.session_id = w.session_id
WHERE r.session_id <> @@SPID
  AND w.wait_time_ms > 0
ORDER BY w.session_id, w.wait_time_ms DESC;
GO
/*
Answers, measured on the lab (SQL Server 2025 CU7) four seconds after the start of the
report, which lasts about twenty seconds. The figures move from one run to the next; their
order of magnitude does not.

1. The engine sees 22 processors and 22 schedulers, those of the host: a processor quota
   on a container does not change what SQL Server sees. Its memory is 4,916 MB, 80 % of the
   6 GB limit (the default memory limit of SQL Server on Linux).
2. The report runs: status running, no current wait, cpu_ms (4,039) equal to elapsed_ms
   (4,039), dop 1, and already 10.2 million logical reads. It computes, on pages that are
   in the cache; it does not wait.
3. No row in sys.dm_os_waiting_tasks: a running task waits for nothing.
4. The Index Seek on the deliveries (node 23) has produced 3.2 million rows for 244
   estimated, and the operators above it as many. An operator far above its estimate is a
   diagnosis in itself: the optimizer built this serial plan with nested loops for 244
   rows. The Sort operators above stay at 0: a sort returns nothing before it has read all
   its input. Two nodes are named ??? by the view.
5. Almost no wait: 12 ms of RESERVED_MEMORY_ALLOCATION_EXT and 1 ms of
   SOS_SCHEDULER_YIELD in four seconds. On a first run after the restore, a few ms of
   PAGEIOLATCH_SH come first, the pages read from disk. The waits say what the session
   waited for, not what it computed.
*/
