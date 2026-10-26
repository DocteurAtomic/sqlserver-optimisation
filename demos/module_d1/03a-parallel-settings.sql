-- Clip D1.3: the parallelism settings, and one dashboard query alone. Runs on the lab, in
-- one session. Messages of STATISTICS TIME are in the Messages tab of SSMS.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- The three settings that decide: two at the instance, one in the database.
SELECT name, value_in_use
FROM sys.configurations
WHERE name IN (N'max degree of parallelism', N'cost threshold for parallelism');
SELECT name, value
FROM sys.database_scoped_configurations
WHERE name = N'MAXDOP';
GO
-- The query of the billing dashboard: the invoice lines of a learner, by last name. The
-- LIKE with a leading wildcard scans the whole table (6,612 pages).
SET STATISTICS TIME ON;
EXEC sys.sp_executesql N'SELECT LineTypeCode, COUNT(*) AS Lines, SUM(NetAmount) AS Amount FROM Enrollment.InvoiceLine WHERE Label LIKE @pattern GROUP BY LineTypeCode;',
     N'@pattern varchar(200)', @pattern = '%Durand';
-- The same query on one thread, for comparison.
EXEC sys.sp_executesql N'SELECT LineTypeCode, COUNT(*) AS Lines, SUM(NetAmount) AS Amount FROM Enrollment.InvoiceLine WHERE Label LIKE @pattern GROUP BY LineTypeCode OPTION (MAXDOP 1);',
     N'@pattern varchar(200)', @pattern = '%Durand';
SET STATISTICS TIME OFF;
GO
-- The cost of each plan, and the degree of parallelism it ran with.
SELECT s.last_dop, s.last_worker_time / 1000 AS cpu_ms, s.last_elapsed_time / 1000 AS elapsed_ms,
       CAST(qp.query_plan.value('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
            (//p:StmtSimple/@StatementSubTreeCost)[1]', 'float') AS decimal(9, 2)) AS plan_cost,
       CASE WHEN t.text LIKE N'%MAXDOP 1%' THEN 'OPTION (MAXDOP 1)' ELSE 'no hint' END AS variant
FROM sys.dm_exec_query_stats AS s
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
CROSS APPLY sys.dm_exec_query_plan(s.plan_handle) AS qp
WHERE t.text LIKE N'%FROM Enrollment.InvoiceLine WHERE Label LIKE @pattern%'
  AND t.text NOT LIKE N'%dm_exec_query_stats%'
ORDER BY s.last_dop DESC;
