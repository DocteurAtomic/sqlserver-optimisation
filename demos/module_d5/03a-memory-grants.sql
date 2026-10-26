-- Clip D5.3: the memory grants of the reports. Runs on the throwaway container while
-- charge.sh runs (alone, it returns the lab at rest). Reads only.
-- 1. The grants now: who asked how much, who got it, who waits (RESOURCE_SEMAPHORE).
-- 2. The largest grant each workload group allows, and the memory of each pool.
USE master;
SET NOCOUNT ON;
GO
-- 1. One row per query that holds or waits for a grant. granted_mb is NULL while the query
--    waits; a grant far below the request means the query gave up waiting and started with
--    its minimum, and its sorts spill to tempdb.
SELECT g.session_id, s.login_name, wg.name AS workload_group, g.dop,
       g.requested_memory_kb / 1024 AS requested_mb,
       g.granted_memory_kb / 1024 AS granted_mb,
       g.used_memory_kb / 1024 AS used_mb,
       g.wait_time_ms
FROM sys.dm_exec_query_memory_grants AS g
JOIN sys.dm_exec_sessions AS s ON s.session_id = g.session_id
JOIN sys.dm_resource_governor_workload_groups AS wg ON wg.group_id = g.group_id
ORDER BY g.session_id;
GO
-- 2. The ceiling of one grant in each group (REQUEST_MAX_MEMORY_GRANT_PERCENT of the memory
--    of its pool), and what each pool holds now.
SELECT wg.name AS workload_group, p.name AS pool,
       wg.request_max_memory_grant_percent_numeric AS grant_percent,
       wg.max_request_grant_memory_kb / 1024 AS largest_grant_so_far_mb,
       p.max_memory_kb / 1024 AS pool_max_mb,
       p.used_memory_kb / 1024 AS pool_used_mb,
       wg.effective_max_dop
FROM sys.dm_resource_governor_workload_groups AS wg
JOIN sys.dm_resource_governor_resource_pools AS p ON p.pool_id = wg.pool_id
WHERE wg.name <> N'internal'
ORDER BY wg.group_id;
