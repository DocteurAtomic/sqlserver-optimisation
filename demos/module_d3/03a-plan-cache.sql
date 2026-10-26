-- Clip D3.3: what fills the plan cache. Runs on the lab, in one session, while charge.sh runs
-- (or just after); it only reads.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The plan cache of the instance, by kind of entry: how many, how big, how many used once.
SELECT cp.objtype, cp.cacheobjtype, COUNT(*) AS plans,
       SUM(CAST(cp.size_in_bytes AS bigint)) / 1048576 AS size_mb,
       SUM(CASE WHEN cp.usecounts = 1 THEN 1 ELSE 0 END) AS used_once
FROM sys.dm_exec_cached_plans AS cp
GROUP BY cp.objtype, cp.cacheobjtype
ORDER BY size_mb DESC;

-- 2. The memory clerk of the ad hoc and prepared plans, next to the buffer pool.
SELECT TOP (4) type, SUM(pages_kb) / 1024 AS mb
FROM sys.dm_os_memory_clerks
GROUP BY type
ORDER BY mb DESC;

-- 3. The same query, many times: query_hash groups the statements that differ only by
--    their literals.
SELECT TOP (3) qs.query_hash, COUNT(*) AS plans, SUM(qs.execution_count) AS executions,
       MIN(RIGHT(REPLACE(REPLACE(t.text, CHAR(13), N''), CHAR(10), N' '), 26)) AS first_end,
       MAX(RIGHT(REPLACE(REPLACE(t.text, CHAR(13), N''), CHAR(10), N' '), 26)) AS last_end
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS t
GROUP BY qs.query_hash
HAVING COUNT(*) > 1
ORDER BY plans DESC;
