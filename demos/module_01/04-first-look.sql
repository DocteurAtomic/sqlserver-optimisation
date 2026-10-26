-- Clip 1.4: the first look at what runs now. Runs on the lab, in one session, while
-- charge.sh runs (it also runs alone: the first queries then return no row). Reads only.
USE master;
GO
-- 1. Who is connected, and who runs something now. A session without a request is idle
--    between two batches.
SELECT s.session_id, s.host_name, s.program_name, s.status AS session_status,
       r.status AS request_status, r.command, r.wait_type, r.wait_time AS wait_ms,
       r.blocking_session_id AS blocked_by, r.cpu_time AS cpu_ms,
       r.total_elapsed_time AS elapsed_ms, r.logical_reads, r.dop
FROM sys.dm_exec_sessions AS s
LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
WHERE s.is_user_process = 1
  AND s.database_id = DB_ID(N'PachadataTraining')
  AND s.session_id <> @@SPID
ORDER BY s.host_name;

-- 2. What the running requests execute: the exact statement, cut out of the batch by its
--    offsets (in bytes, hence the divisions by 2: the text is Unicode).
SELECT r.session_id, s.host_name, r.status, r.wait_type,
       SUBSTRING(t.text, r.statement_start_offset / 2 + 1,
                 (CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
                       ELSE r.statement_end_offset END - r.statement_start_offset) / 2 + 1)
           AS statement_text
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE s.is_user_process = 1
  AND s.database_id = DB_ID(N'PachadataTraining')
  AND r.session_id <> @@SPID
ORDER BY s.host_name;

-- 3. The tasks that wait now, and on what. A parallel request has several tasks.
SELECT wt.session_id, s.host_name, wt.exec_context_id, wt.wait_type,
       wt.wait_duration_ms, wt.blocking_session_id
FROM sys.dm_os_waiting_tasks AS wt
JOIN sys.dm_exec_sessions AS s ON s.session_id = wt.session_id
WHERE s.is_user_process = 1
  AND s.database_id = DB_ID(N'PachadataTraining')
  AND wt.session_id <> @@SPID
ORDER BY s.host_name, wt.exec_context_id;
GO
-- 4. What has cost the most since its plan entered the cache: one row per statement, the
--    total and the average per execution. A query cheap per execution and run thousands
--    of times can cost more than a report. The last column opens the cached plan in SSMS.
--    The plan is read for these five statements only, after the sort.
WITH top_reads AS (
    SELECT TOP (5) qs.execution_count,
           qs.total_worker_time,
           qs.total_logical_reads,
           qs.statement_start_offset,
           qs.statement_end_offset,
           qs.sql_handle,
           qs.plan_handle
    FROM sys.dm_exec_query_stats AS qs
    CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
    WHERE pa.attribute = N'dbid'
      AND CONVERT(int, pa.value) = DB_ID(N'PachadataTraining')
    ORDER BY qs.total_logical_reads DESC
)
SELECT tr.execution_count,
       tr.total_worker_time / 1000 AS total_cpu_ms,
       tr.total_logical_reads,
       tr.total_logical_reads / tr.execution_count AS avg_logical_reads,
       tr.total_worker_time / tr.execution_count / 1000 AS avg_cpu_ms,
       LEFT(SUBSTRING(t.text, tr.statement_start_offset / 2 + 1,
                      (CASE tr.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
                            ELSE tr.statement_end_offset END - tr.statement_start_offset) / 2 + 1),
            80) AS statement_start,
       qp.query_plan
FROM top_reads AS tr
CROSS APPLY sys.dm_exec_sql_text(tr.sql_handle) AS t
OUTER APPLY sys.dm_exec_query_plan(tr.plan_handle) AS qp
ORDER BY tr.total_logical_reads DESC;
GO
