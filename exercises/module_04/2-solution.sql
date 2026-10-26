-- Module 4 exercise: solution. Runs on the lab, in one session, after 1-start.sql.
-- It leaves nothing behind: the forcing and the hint are removed, and the procedure changed in
-- part 4 gets its original definition back. Part 3 makes a query fail on purpose (error
-- 8778): the error is caught, so the script runs to the end.
USE PachadataTraining;
SET NOCOUNT ON;
SET ARITHABORT ON;
GO
-- Part 1. Finding the regression.
-- 1.1 The most expensive queries of the last hour, by total CPU time.
SELECT TOP (5)
       q.query_id,
       OBJECT_NAME(q.object_id) AS module_name,
       COUNT(DISTINCT p.plan_id) AS plans,
       SUM(rs.count_executions) AS executions,
       CAST(SUM(rs.avg_cpu_time * rs.count_executions) / 1000 AS int) AS total_cpu_ms,
       CAST(SUM(rs.avg_logical_io_reads * rs.count_executions) AS bigint) AS total_reads
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE i.start_time >= DATEADD(HOUR, -1, SYSUTCDATETIME())
GROUP BY q.query_id, q.object_id
ORDER BY total_cpu_ms DESC;

-- 1.2 The plans of the procedure, interval by interval.
SELECT i.start_time, rs.plan_id, rs.count_executions,
       CAST(rs.avg_logical_io_reads AS int) AS avg_reads,
       rs.min_logical_io_reads AS min_reads, rs.max_logical_io_reads AS max_reads,
       CAST(rs.avg_cpu_time AS int) AS avg_cpu_us,
       CASE WHEN CAST(p.query_plan AS nvarchar(max)) LIKE N'%Lookup="1"%'
            THEN 'seek + RID lookup' ELSE 'table scan' END AS plan_shape
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.ProspectsByParameter')
ORDER BY i.start_time, rs.plan_id;

-- 1.3 What the engine recommends.
SELECT reason, JSON_VALUE(details, '$.implementationDetails.script') AS script
FROM sys.dm_db_tuning_recommendations;
GO
-- Part 2. Forcing, and measuring.
-- 2.1 The plan with the fewest reads on average, forced.
DECLARE @query_id bigint, @plan_id bigint;
SELECT TOP (1) @query_id = p.query_id, @plan_id = p.plan_id
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
WHERE q.object_id = OBJECT_ID(N'Contact.ProspectsByParameter')
GROUP BY p.query_id, p.plan_id
ORDER BY SUM(rs.avg_logical_io_reads * rs.count_executions) / SUM(rs.count_executions);
EXEC sys.sp_query_store_force_plan @query_id = @query_id, @plan_id = @plan_id;
SELECT @query_id AS query_id, @plan_id AS forced_plan_id;
GO
-- 2.2 The sequence of the load replayed: recompilation, '9%' first, then one zip code.
EXEC sys.sp_recompile N'Contact.ProspectsByParameter';
GO
CREATE TABLE #Sink (LastName varchar(50), FirstName varchar(50));
SET STATISTICS IO ON;
INSERT #Sink EXEC Contact.ProspectsByParameter @zip = '9%';
INSERT #Sink EXEC Contact.ProspectsByParameter @zip = '10001';
SET STATISTICS IO OFF;
DROP TABLE #Sink;
GO
-- 2.3 The forcing: applied, no failure.
SELECT p.plan_id, p.is_forced_plan, p.plan_forcing_type_desc,
       p.force_failure_count, p.last_force_failure_reason_desc
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.ProspectsByParameter')
ORDER BY p.plan_id;
GO
-- Part 3. Blocking an ad hoc report (SQL Server 2025).
-- 3.1 The report, run once: Query Store captures it.
SELECT TOP (5) City, COUNT(*) AS Prospects FROM Contact.ProspectUS GROUP BY City ORDER BY Prospects DESC;
GO
DECLARE @query_id bigint = (
    SELECT q.query_id
    FROM sys.query_store_query AS q
    JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    WHERE qt.query_sql_text LIKE N'SELECT TOP (5) City, COUNT(*) AS Prospects%');
SELECT @query_id AS report_query_id;
-- 3.2 The hint that blocks it.
EXEC sys.sp_query_store_set_hints @query_id = @query_id,
     @query_hints = N'OPTION (USE HINT (''ABORT_QUERY_EXECUTION''))';
GO
-- 3.3 The same report again: error 8778, caught here.
BEGIN TRY
    SELECT TOP (5) City, COUNT(*) AS Prospects FROM Contact.ProspectUS GROUP BY City ORDER BY Prospects DESC;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO
-- 3.4 What Query Store kept: one Regular execution, then Exception ones. A new query or a
-- new execution can take a second or two to show in the views: the script waits.
WAITFOR DELAY '00:00:02';
SELECT p.query_id, rs.execution_type_desc, SUM(rs.count_executions) AS executions
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
WHERE qt.query_sql_text LIKE N'SELECT TOP (5) City, COUNT(*) AS Prospects%'
GROUP BY p.query_id, rs.execution_type_desc;
SELECT query_id, query_hint_text, query_hint_failure_count
FROM sys.query_store_query_hints;
-- 3.5 The hint removed.
DECLARE @query_id bigint = (SELECT query_id FROM sys.query_store_query_hints);
EXEC sys.sp_query_store_clear_hints @query_id = @query_id;
SELECT COUNT(*) AS hints_left FROM sys.query_store_query_hints;
GO
-- Part 4. When the code changes.
-- 4.1 The original definition kept, to put it back at the end.
SELECT OBJECT_DEFINITION(OBJECT_ID(N'Contact.ProspectsByParameter')) AS definition
INTO #ProcDef;
GO
-- 4.2 A comment written before the statement: the statement text does not change.
CREATE OR ALTER PROCEDURE Contact.ProspectsByParameter
    @zip varchar(10) = NULL
AS BEGIN
    SET NOCOUNT ON;

    -- The plan of this query is forced by Query Store (sys.query_store_plan, is_forced_plan).
    SELECT LastName, FirstName FROM Contact.ProspectUS
    WHERE ZipCode LIKE @zip;
END;
GO
CREATE TABLE #Sink (LastName varchar(50), FirstName varchar(50));
INSERT #Sink EXEC Contact.ProspectsByParameter @zip = '9%';
DROP TABLE #Sink;
WAITFOR DELAY '00:00:02';
SELECT q.query_id, p.plan_id, p.is_forced_plan, p.last_execution_time,
       CASE WHEN CAST(p.query_plan AS nvarchar(max)) LIKE N'%Lookup="1"%'
            THEN 'seek + RID lookup' ELSE 'table scan' END AS plan_shape
FROM sys.query_store_query AS q
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.ProspectsByParameter')
ORDER BY p.last_execution_time DESC;
GO
-- 4.3 The statement itself changed (one more column): a new query for Query Store, which
-- the forcing does not follow.
CREATE OR ALTER PROCEDURE Contact.ProspectsByParameter
    @zip varchar(10) = NULL
AS BEGIN
    SET NOCOUNT ON;

    SELECT LastName, FirstName, City FROM Contact.ProspectUS
    WHERE ZipCode LIKE @zip;
END;
GO
CREATE TABLE #Sink (LastName varchar(50), FirstName varchar(50), City varchar(255));
INSERT #Sink EXEC Contact.ProspectsByParameter @zip = '10001';
DROP TABLE #Sink;
WAITFOR DELAY '00:00:02';
SELECT q.query_id, p.plan_id, p.is_forced_plan, LEFT(qt.query_sql_text, 60) AS query_text
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.ProspectsByParameter')
ORDER BY q.query_id, p.plan_id;
GO
-- Cleanup: the forcing removed, the original procedure back.
DECLARE @query_id bigint, @plan_id bigint;
SELECT @query_id = p.query_id, @plan_id = p.plan_id
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.ProspectsByParameter') AND p.is_forced_plan = 1;
EXEC sys.sp_query_store_unforce_plan @query_id = @query_id, @plan_id = @plan_id;
DROP PROCEDURE Contact.ProspectsByParameter;
DECLARE @def nvarchar(max) = (SELECT definition FROM #ProcDef);
EXEC (@def);
DROP TABLE #ProcDef;
GO
SELECT COUNT(*) AS forced_plans_left
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.ProspectsByParameter') AND p.is_forced_plan = 1;
SELECT CASE WHEN OBJECT_DEFINITION(OBJECT_ID(N'Contact.ProspectsByParameter')) LIKE N'%LastName, FirstName FROM%'
            THEN 'original definition' ELSE 'changed' END AS procedure_state;
