-- Clip D1.2: the memory settings and what the engine has taken. Runs on the lab, in one
-- session; it only reads.
USE master;
SET NOCOUNT ON;
GO
-- The two bounds of the instance. sys.configurations shows them without sp_configure.
SELECT name, value, value_in_use
FROM sys.configurations
WHERE name IN (N'max server memory (MB)', N'min server memory (MB)')
ORDER BY name;

-- The target follows max server memory; committed is what the instance has taken so far.
SELECT physical_memory_kb / 1024 AS physical_memory_mb,
       committed_target_kb / 1024 AS target_mb,
       committed_kb / 1024 AS committed_mb
FROM sys.dm_os_sys_info;

-- Who holds the memory: the data cache (buffer pool), the memory reserved for queries,
-- the plan cache...
SELECT TOP (6) type, SUM(pages_kb) / 1024 AS mb
FROM sys.dm_os_memory_clerks
GROUP BY type
ORDER BY mb DESC;

-- The memory for sorts and hashes: the resource semaphore of the default pool. A query asks
-- for its grant before it runs, and waits (RESOURCE_SEMAPHORE) when there is not enough.
SELECT resource_semaphore_id, target_memory_kb / 1024 AS target_mb,
       available_memory_kb / 1024 AS available_mb,
       granted_memory_kb / 1024 AS granted_mb, grantee_count, waiter_count
FROM sys.dm_exec_query_resource_semaphores
WHERE pool_id = 2;

SELECT name, request_max_memory_grant_percent
FROM sys.dm_resource_governor_workload_groups
WHERE name = N'default';
