-- Clip D3.3: optimize for ad hoc workloads, measured. Runs in one session, while charge.sh
-- runs. Lasts one minute.
-- ci: skip (it changes the configuration of the instance; 99-cleanup.sql puts it back)
-- The option is an instance setting: every database of the instance gets it. Its
-- RECONFIGURE does not empty the plan cache, so the plans already there stay: the script
-- empties the cache of PachadataTraining alone, to measure what the option does to new
-- plans. On a production server, the option alone, without emptying anything.
USE master;
SET NOCOUNT ON;
GO
EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure N'optimize for ad hoc workloads', 1;
RECONFIGURE;
GO
USE PachadataTraining;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
SELECT RTRIM(counter_name) AS counter_name, cntr_value, SYSDATETIME() AS read_at
INTO #Before
FROM sys.dm_os_performance_counters
WHERE object_name LIKE N'%:SQL Statistics%'
  AND counter_name IN (N'Batch Requests/sec', N'SQL Compilations/sec');

WAITFOR DELAY '00:01:00';

-- 1. Batches and compilations per second over the minute.
SELECT b.counter_name,
       (p.cntr_value - b.cntr_value) / (DATEDIFF(MILLISECOND, b.read_at, SYSDATETIME()) / 1000) AS per_second
FROM #Before AS b
JOIN sys.dm_os_performance_counters AS p
  ON p.object_name LIKE N'%:SQL Statistics%' AND RTRIM(p.counter_name) = b.counter_name;

-- 2. The plan cache after one minute with the option.
SELECT cp.objtype, cp.cacheobjtype, COUNT(*) AS plans,
       SUM(CAST(cp.size_in_bytes AS bigint)) / 1024 AS size_kb,
       SUM(CASE WHEN cp.usecounts = 1 THEN 1 ELSE 0 END) AS used_once
FROM sys.dm_exec_cached_plans AS cp
WHERE cp.objtype = N'Adhoc'
GROUP BY cp.objtype, cp.cacheobjtype
ORDER BY size_kb DESC;
