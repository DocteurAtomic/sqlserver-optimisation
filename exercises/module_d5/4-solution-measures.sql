-- Module D5 exercise: solution of part 4. Runs on your lab, as sa, after
-- 3-export-as-export-user.sql.
-- ci: skip (it reads the configuration of the exercise)
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- One row per cached plan of the export: the same text compiled for sa (group default)
-- and for export_user (group Export) gives two entries, told apart by last_dop.
SELECT qs.execution_count AS runs, qs.last_dop,
       qs.last_grant_kb / 1024 AS last_grant_mb,
       qs.last_used_grant_kb / 1024 AS last_used_mb,
       qs.last_spills AS last_pages_spilled,
       qs.last_worker_time / 1000 AS last_cpu_ms,
       qs.last_elapsed_time / 1000 AS last_elapsed_ms
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE st.text LIKE N'%SELECT TOP (100) ContactId, ModuleId%'
  AND st.text NOT LIKE N'%dm_exec_query_stats%'
ORDER BY qs.last_dop DESC;
GO
-- What the governor counted for each group: the largest grant, tempdb, the violations.
SELECT g.name AS workload_group, p.name AS pool,
       g.max_request_grant_memory_kb / 1024 AS largest_grant_mb,
       p.max_memory_kb / 1024 AS pool_max_mb,
       g.effective_max_dop,
       g.peak_tempdb_data_space_kb / 1024 AS tempdb_peak_mb,
       g.total_tempdb_data_limit_violation_count AS violations
FROM sys.dm_resource_governor_workload_groups AS g
JOIN sys.dm_resource_governor_resource_pools AS p ON p.pool_id = g.pool_id
WHERE g.name IN (N'default', N'Export');
GO
