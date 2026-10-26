-- Clip D1.4: the fix, at the instance, without touching the code. Runs in one session.
-- ci: skip (it changes the configuration of the instance; 99-cleanup.sql puts it back)
-- Values for the lab container, 6 GB and 4 processors: the engine sees 4,916 MB and 22
-- processors, of which the container grants 4. Each RECONFIGURE of these options empties
-- the plan cache of the whole instance: on a production server, outside the peak hours.
USE master;
SET NOCOUNT ON;
GO
EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
-- Memory: 75 % of what the engine sees (4,916 MB), under the 80 % ceiling of Linux.
EXEC sys.sp_configure N'max server memory (MB)', 3687;
-- Parallelism: no more threads than the processors of the container, and only for the
-- queries that cost more than 50.
EXEC sys.sp_configure N'max degree of parallelism', 4;
EXEC sys.sp_configure N'cost threshold for parallelism', 50;
RECONFIGURE;
GO
WAITFOR DELAY '00:00:05';
SELECT name, value_in_use
FROM sys.configurations
WHERE name IN (N'max server memory (MB)', N'max degree of parallelism',
               N'cost threshold for parallelism')
ORDER BY name;
SELECT committed_target_kb / 1024 AS target_mb
FROM sys.dm_os_sys_info;
-- The database stays at 0: the instance setting applies to it.
SELECT name, value
FROM PachadataTraining.sys.database_scoped_configurations
WHERE name = N'MAXDOP';
GO
-- The dashboard query alone, after the fix: its plan costs 5.38, under the new threshold.
USE PachadataTraining;
SET STATISTICS TIME ON;
EXEC sys.sp_executesql N'SELECT LineTypeCode, COUNT(*) AS Lines, SUM(NetAmount) AS Amount FROM Enrollment.InvoiceLine WHERE Label LIKE @pattern GROUP BY LineTypeCode;',
     N'@pattern varchar(200)', @pattern = '%Durand';
SET STATISTICS TIME OFF;
GO
SELECT s.last_dop, s.last_worker_time / 1000 AS cpu_ms, s.last_elapsed_time / 1000 AS elapsed_ms
FROM sys.dm_exec_query_stats AS s
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
WHERE t.text LIKE N'%FROM Enrollment.InvoiceLine WHERE Label LIKE @pattern GROUP BY LineTypeCode;%'
  AND t.text NOT LIKE N'%dm_exec_query_stats%';
