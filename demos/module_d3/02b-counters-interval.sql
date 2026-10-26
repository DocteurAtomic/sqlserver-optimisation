-- Clip D3.2: the useful counters over one minute. Runs on the lab, in one session, while
-- charge.sh runs (it also runs alone). Lasts one minute.
USE master;
SET NOCOUNT ON;
GO
-- The counters read, by object and name. The object name starts with SQLServer: on a
-- default instance and with MSSQL$<name>: on a named instance, hence the LIKE on the end,
-- after an RTRIM: the names are padded with spaces up to 128 characters.
CREATE TABLE #Wanted (object_suffix nvarchar(64), counter_name nvarchar(128), instance_name nvarchar(128));
INSERT #Wanted VALUES
 (N':SQL Statistics', N'Batch Requests/sec', N''),
 (N':SQL Statistics', N'SQL Compilations/sec', N''),
 (N':SQL Statistics', N'SQL Re-Compilations/sec', N''),
 (N':Buffer Manager', N'Page life expectancy', N''),
 (N':Buffer Manager', N'Page reads/sec', N''),
 (N':Memory Manager', N'Total Server Memory (KB)', N''),
 (N':Memory Manager', N'Target Server Memory (KB)', N''),
 (N':Memory Manager', N'Stolen Server Memory (KB)', N''),
 (N':Memory Manager', N'Database Cache Memory (KB)', N''),
 (N':Plan Cache', N'Cache Pages', N'SQL Plans'),
 (N':Plan Cache', N'Cache Object Counts', N'SQL Plans');

SELECT w.counter_name, w.instance_name, p.cntr_type, p.cntr_value, SYSDATETIME() AS read_at
INTO #Before
FROM #Wanted AS w
JOIN sys.dm_os_performance_counters AS p
  ON RTRIM(p.object_name) LIKE N'%' + w.object_suffix
 AND RTRIM(p.counter_name) = w.counter_name AND RTRIM(p.instance_name) = w.instance_name;
-- The optimizations, counted by the optimizer itself.
SELECT occurrence INTO #Optimizations
FROM sys.dm_exec_query_optimizer_info
WHERE counter = N'optimizations';

WAITFOR DELAY '00:01:00';

-- Cumulative counters (272696576) per second over the interval; the others as they are now.
SELECT b.counter_name, b.instance_name,
       CASE WHEN b.cntr_type = 272696576
            THEN (p.cntr_value - b.cntr_value)
                 / (DATEDIFF(MILLISECOND, b.read_at, SYSDATETIME()) / 1000)
            ELSE p.cntr_value END AS value,
       CASE WHEN b.cntr_type = 272696576 THEN N'per second' ELSE N'now' END AS unit
FROM #Before AS b
JOIN #Wanted AS w ON w.counter_name = b.counter_name AND w.instance_name = b.instance_name
JOIN sys.dm_os_performance_counters AS p
  ON RTRIM(p.object_name) LIKE N'%' + w.object_suffix
 AND RTRIM(p.counter_name) = b.counter_name AND RTRIM(p.instance_name) = b.instance_name
ORDER BY b.counter_name;

SELECT (o.occurrence - b.occurrence) / 60 AS optimizations_per_second
FROM sys.dm_exec_query_optimizer_info AS o
CROSS JOIN #Optimizations AS b
WHERE o.counter = N'optimizations';
