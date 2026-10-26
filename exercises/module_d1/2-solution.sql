-- Module D1 exercise: solution. Runs on your lab, in one session, after 1-start.sql.
-- ci: skip (it changes the configuration of the instance, then puts it back)
-- Parts 2 and 3 change cost threshold for parallelism and max server memory; the end of the
-- script puts back the values of the lab (5 and 2,147,483,647, show advanced options 0).
-- It lasts a little over a minute (part 3 waits for the counter).
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- Part 1. One query, two degrees of parallelism. The waits of the session are read before
-- and after each run: sys.dm_exec_session_wait_stats adds up since the connection opened.
SELECT wait_type, waiting_tasks_count, wait_time_ms
INTO #W FROM sys.dm_exec_session_wait_stats WHERE session_id = @@SPID;
SET STATISTICS TIME ON;
SELECT TOP (5) ContactId, COUNT(*) AS Deliveries, SUM(CAST(Opened AS int)) AS Opened
FROM Marketing.Delivery GROUP BY ContactId ORDER BY Deliveries DESC OPTION (MAXDOP 4);
SET STATISTICS TIME OFF;
SELECT N'MAXDOP 4' AS run, w.wait_type,
       w.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) AS waits,
       w.wait_time_ms - ISNULL(b.wait_time_ms, 0) AS wait_ms
FROM sys.dm_exec_session_wait_stats AS w
LEFT JOIN #W AS b ON b.wait_type = w.wait_type
WHERE w.session_id = @@SPID AND w.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) > 0
ORDER BY wait_ms DESC;
DROP TABLE #W;
GO
SELECT wait_type, waiting_tasks_count, wait_time_ms
INTO #W FROM sys.dm_exec_session_wait_stats WHERE session_id = @@SPID;
SET STATISTICS TIME ON;
SELECT TOP (5) ContactId, COUNT(*) AS Deliveries, SUM(CAST(Opened AS int)) AS Opened
FROM Marketing.Delivery GROUP BY ContactId ORDER BY Deliveries DESC OPTION (MAXDOP 1);
SET STATISTICS TIME OFF;
SELECT N'MAXDOP 1' AS run, w.wait_type,
       w.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) AS waits,
       w.wait_time_ms - ISNULL(b.wait_time_ms, 0) AS wait_ms
FROM sys.dm_exec_session_wait_stats AS w
LEFT JOIN #W AS b ON b.wait_type = w.wait_type
WHERE w.session_id = @@SPID AND w.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) > 0
ORDER BY wait_ms DESC;
DROP TABLE #W;
GO
-- Part 2. The same aggregate at three degrees, five times each, the plan cache of the base
-- emptied first. The database has MAXDOP 2: the query without a hint takes it.
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
SELECT TOP (10) City, COUNT(*) AS Prospects FROM Contact.ProspectUS GROUP BY City ORDER BY Prospects DESC OPTION (MAXDOP 1);
GO 5
SELECT TOP (10) City, COUNT(*) AS Prospects FROM Contact.ProspectUS GROUP BY City ORDER BY Prospects DESC OPTION (MAXDOP 4);
GO 5
SELECT TOP (10) City, COUNT(*) AS Prospects FROM Contact.ProspectUS GROUP BY City ORDER BY Prospects DESC;
GO 5
-- What each variant cost. The cost of the MAXDOP 1 plan is the cost of the serial plan,
-- the one the optimizer compares with cost threshold for parallelism.
SELECT s.last_dop, s.execution_count,
       s.total_worker_time / s.execution_count / 1000 AS avg_cpu_ms,
       s.total_elapsed_time / s.execution_count / 1000 AS avg_elapsed_ms,
       CAST(qp.query_plan.value('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
            (//p:StmtSimple/@StatementSubTreeCost)[1]', 'float') AS decimal(9, 2)) AS plan_cost
FROM sys.dm_exec_query_stats AS s
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
CROSS APPLY sys.dm_exec_query_plan(s.plan_handle) AS qp
WHERE t.text LIKE N'SELECT TOP (10) City, COUNT(*) AS Prospects FROM Contact.ProspectUS%'
ORDER BY s.last_dop;
GO
-- The threshold raised above the cost of the serial plan (about 16 on the lab): the query
-- without a hint goes back to one thread. The RECONFIGURE empties the plan cache of the
-- whole instance.
EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure N'cost threshold for parallelism', 25;
RECONFIGURE;
GO
SELECT TOP (10) City, COUNT(*) AS Prospects FROM Contact.ProspectUS GROUP BY City ORDER BY Prospects DESC;
GO 5
SELECT s.last_dop, s.execution_count,
       s.total_worker_time / s.execution_count / 1000 AS avg_cpu_ms,
       s.total_elapsed_time / s.execution_count / 1000 AS avg_elapsed_ms
FROM sys.dm_exec_query_stats AS s
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
WHERE t.text LIKE N'SELECT TOP (10) City, COUNT(*) AS Prospects FROM Contact.ProspectUS GROUP BY City ORDER BY Prospects DESC;%';
GO
-- Part 3. max server memory for an instance alone, after Microsoft's guidance: the memory the
-- engine sees, minus the stacks of the workers (2 MB each in 64 bits), which max server
-- memory does not cover, then 75 % of the rest.
USE master;
GO
SELECT COUNT(*) AS cached_plans_before FROM sys.dm_exec_cached_plans;
DECLARE @physical int, @workers int, @max int;
SELECT @physical = physical_memory_kb / 1024, @workers = max_workers_count FROM sys.dm_os_sys_info;
SET @max = (@physical - @workers * 2) * 3 / 4;
SELECT @physical AS physical_mb, @workers * 2 AS worker_stacks_mb, @max AS max_server_memory_mb;
EXEC sys.sp_configure N'max server memory (MB)', @max;
RECONFIGURE;
SELECT COUNT(*) AS cached_plans_after FROM sys.dm_exec_cached_plans;
GO
WAITFOR DELAY '00:00:10';
-- The DMV follows the RECONFIGURE; the performance counter can lag behind.
SELECT committed_target_kb / 1024 AS target_mb, committed_kb / 1024 AS committed_mb
FROM sys.dm_os_sys_info;
SELECT RTRIM(counter_name) AS counter_name, cntr_value / 1024 AS mb
FROM sys.dm_os_performance_counters
WHERE counter_name IN (N'Target Server Memory (KB)', N'Total Server Memory (KB)');
GO
WAITFOR DELAY '00:00:50';
SELECT RTRIM(counter_name) AS counter_name, cntr_value / 1024 AS mb
FROM sys.dm_os_performance_counters
WHERE counter_name IN (N'Target Server Memory (KB)', N'Total Server Memory (KB)');
GO
-- Back to the values of the lab.
EXEC sys.sp_configure N'max server memory (MB)', 2147483647;
EXEC sys.sp_configure N'cost threshold for parallelism', 5;
RECONFIGURE;
EXEC sys.sp_configure N'show advanced options', 0;
RECONFIGURE;
SELECT name, value_in_use
FROM sys.configurations
WHERE name IN (N'max server memory (MB)', N'cost threshold for parallelism', N'show advanced options')
ORDER BY name;
