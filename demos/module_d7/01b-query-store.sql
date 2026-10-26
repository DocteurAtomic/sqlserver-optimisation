-- Clip D7.1, the morning routine, step 2: what Query Store kept of the night. Runs on the
-- lab, in one session, after charge.sh has played the night. Reads only.
-- Query Store times are in UTC. On a production server, @since is
-- DATEADD(HOUR, -24, SYSUTCDATETIME()); on the lab, the restore of 00-setup.sql.
USE PachadataTraining;
SET NOCOUNT ON;
GO
DECLARE @since datetime2 = (
    SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, SYSDATETIME(), SYSUTCDATETIME()), MAX(restore_date))
    FROM msdb.dbo.restorehistory WHERE destination_database_name = DB_NAME());

-- 1. The queries that ran with more than one plan since the evening, each plan with its
--    executions and its mean reads. A plan that reads several times more than the other one
--    for the same query is a regression to look at. Each plan must have run ten times at
--    least: a cursor, for instance, has a plan for its opening, run once, and one for its
--    fetches.
WITH plans AS (
    SELECT p.query_id, p.plan_id,
           MIN(i.start_time) AS first_interval,
           SUM(rs.count_executions) AS executions,
           SUM(rs.avg_logical_io_reads * rs.count_executions) / SUM(rs.count_executions) AS avg_reads
    FROM sys.query_store_runtime_stats AS rs
    JOIN sys.query_store_runtime_stats_interval AS i
      ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
    JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
    WHERE i.end_time > @since
    GROUP BY p.query_id, p.plan_id
)
SELECT p.query_id, OBJECT_NAME(q.object_id) AS module_name, p.plan_id,
       CONVERT(char(5), CAST(p.first_interval AS time), 108) AS first_seen_utc,
       p.executions, CAST(p.avg_reads AS int) AS avg_reads,
       CAST(MAX(p.avg_reads) OVER (PARTITION BY p.query_id)
            / NULLIF(MIN(p.avg_reads) OVER (PARTITION BY p.query_id), 0) AS decimal(10, 1)) AS ratio
FROM plans AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE p.query_id IN (SELECT query_id FROM plans GROUP BY query_id
                     HAVING COUNT(*) > 1 AND MIN(executions) >= 10)
ORDER BY ratio DESC, p.query_id, p.first_interval;

-- 2. The executions that did not end normally: aborted (the client gave up, a timeout) or
--    ended by an error. Query Store records them when they end.
SELECT q.query_id, OBJECT_NAME(q.object_id) AS module_name, rs.execution_type_desc,
       SUM(rs.count_executions) AS executions,
       CAST(MAX(rs.max_duration) / 1000 AS int) AS max_duration_ms,
       LEFT(REPLACE(qt.query_sql_text, CHAR(10), ' '), 70) AS query_text
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
WHERE i.end_time > @since AND rs.execution_type <> 0
GROUP BY q.query_id, q.object_id, rs.execution_type_desc, qt.query_sql_text
ORDER BY executions DESC;

-- 3. The waits of the night by category, the longest first, with the query that waited.
SELECT TOP (5) ws.wait_category_desc, q.query_id, OBJECT_NAME(q.object_id) AS module_name,
       SUM(ws.total_query_wait_time_ms) / 1000 AS wait_s
FROM sys.query_store_wait_stats AS ws
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = ws.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON p.plan_id = ws.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE i.end_time > @since
GROUP BY ws.wait_category_desc, q.query_id, q.object_id
ORDER BY wait_s DESC;

-- 4. The regressions the engine noticed by itself, even with automatic tuning off (module 4),
--    with the estimated gain as Learn computes it (page "Automatic tuning"): the executions
--    of both plans times the difference of their mean CPU time, in seconds.
SELECT reason, score,
       JSON_VALUE(state, '$.currentValue') AS state,
       JSON_VALUE(details, '$.implementationDetails.script') AS script,
       CAST((d.regressedPlanExecutionCount + d.recommendedPlanExecutionCount)
            * (d.regressedPlanCpuTimeAverage - d.recommendedPlanCpuTimeAverage) / 1000000
            AS decimal(10, 1)) AS estimated_gain_s,
       IIF(d.regressedPlanErrorCount > d.recommendedPlanErrorCount, 'YES', 'NO') AS error_prone
FROM sys.dm_db_tuning_recommendations
CROSS APPLY OPENJSON(details, '$.planForceDetails')
    WITH (regressedPlanErrorCount int, recommendedPlanErrorCount int,
          regressedPlanExecutionCount int, regressedPlanCpuTimeAverage float,
          recommendedPlanExecutionCount int, recommendedPlanCpuTimeAverage float) AS d;
GO
