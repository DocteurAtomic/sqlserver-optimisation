-- Clip D3.4: the fix that the DBA can make without the code of the website. Runs in one
-- session, while charge.sh runs. Lasts one minute.
-- ci: skip (it needs the load; the next module's 00-setup.sql restores the database)
-- PARAMETERIZATION FORCED is an option of the database: the engine replaces the literals
-- of every query by parameters before it looks in the plan cache. The real fix is in the
-- website: parameters passed by the client library (sp_executesql), not concatenated.
USE master;
SET NOCOUNT ON;
GO
ALTER DATABASE PachadataTraining SET PARAMETERIZATION FORCED;
GO
SELECT CONVERT(char(12), CAST(SYSDATETIME() AS time(3))) AS changed_at;
SELECT name, is_parameterization_forced
FROM sys.databases
WHERE name = N'PachadataTraining';
GO
-- One minute of the load with the option: batches, compilations and optimizations.
SELECT RTRIM(counter_name) AS counter_name, cntr_value, SYSDATETIME() AS read_at
INTO #Before
FROM sys.dm_os_performance_counters
WHERE object_name LIKE N'%:SQL Statistics%'
  AND counter_name IN (N'Batch Requests/sec', N'SQL Compilations/sec')
UNION ALL
SELECT N'optimizations', occurrence, SYSDATETIME()
FROM sys.dm_exec_query_optimizer_info
WHERE counter = N'optimizations';

WAITFOR DELAY '00:01:00';

SELECT b.counter_name,
       (x.value - b.cntr_value) / (DATEDIFF(MILLISECOND, b.read_at, SYSDATETIME()) / 1000) AS per_second
FROM #Before AS b
CROSS APPLY (SELECT cntr_value FROM sys.dm_os_performance_counters
             WHERE object_name LIKE N'%:SQL Statistics%' AND RTRIM(counter_name) = b.counter_name
             UNION ALL
             SELECT occurrence FROM sys.dm_exec_query_optimizer_info
             WHERE counter = N'optimizations' AND b.counter_name = N'optimizations') AS x(value);
GO
USE PachadataTraining;
-- The two pages of the website now share prepared plans, compiled once.
SELECT cp.objtype, cp.usecounts, cp.size_in_bytes / 1024 AS size_kb,
       CONVERT(char(12), CAST(qs.created AS time(3))) AS created_at,
       SUBSTRING(t.text, CHARINDEX(N'where', t.text), 30) AS where_clause
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS t
OUTER APPLY (SELECT MIN(creation_time) AS created
             FROM sys.dm_exec_query_stats AS s
             WHERE s.plan_handle = cp.plan_handle) AS qs
WHERE cp.objtype = N'Prepared'
  AND t.text LIKE N'%where%Id = @0%'
ORDER BY cp.usecounts DESC;
