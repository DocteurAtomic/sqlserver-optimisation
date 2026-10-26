-- Clip 4.2: finding the regression in Query Store. Runs on the lab, in one session, after
-- 00-setup.sql. The columns of sys.query_store_runtime_stats are averages per interval
-- (microseconds for times): multiply by count_executions before adding them up.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The most expensive queries of the last hour, by total CPU time.
SELECT TOP (5)
       q.query_id,
       OBJECT_NAME(q.object_id) AS module_name,
       COUNT(DISTINCT p.plan_id) AS plans,
       SUM(rs.count_executions) AS executions,
       CAST(SUM(rs.avg_cpu_time * rs.count_executions) / 1000 AS int) AS total_cpu_ms,
       CAST(SUM(rs.avg_logical_io_reads * rs.count_executions) AS bigint) AS total_reads,
       LEFT(qt.query_sql_text, 50) AS query_text
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
WHERE i.start_time >= DATEADD(HOUR, -1, SYSUTCDATETIME())
GROUP BY q.query_id, q.object_id, qt.query_sql_text
ORDER BY total_cpu_ms DESC;
GO
-- 2. The plans of the query, side by side: the spread between min and max reads of a plan
--    says whether it serves every value of the parameter.
SELECT p.plan_id, p.query_plan_hash,
       MIN(i.start_time) AS first_interval, MAX(i.end_time) AS last_interval,
       SUM(rs.count_executions) AS executions,
       CAST(SUM(rs.avg_logical_io_reads * rs.count_executions) / SUM(rs.count_executions) AS int) AS avg_reads,
       MIN(rs.min_logical_io_reads) AS min_reads,
       MAX(rs.max_logical_io_reads) AS max_reads,
       CAST(SUM(rs.avg_cpu_time * rs.count_executions) / SUM(rs.count_executions) AS int) AS avg_cpu_us,
       CASE WHEN CAST(p.query_plan AS nvarchar(max)) LIKE N'%Lookup="1"%'
            THEN 'seek + key lookup' ELSE 'clustered index scan' END AS plan_shape
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
GROUP BY p.plan_id, p.query_plan_hash, CAST(p.query_plan AS nvarchar(max))
ORDER BY first_interval;
GO
-- 3. Two periods of the same query compared, interval by interval, all plans together.
--    In production, with one-hour intervals, compare a day with the same day of the
--    previous week.
SELECT i.start_time, SUM(rs.count_executions) AS executions,
       CAST(SUM(rs.avg_logical_io_reads * rs.count_executions) / SUM(rs.count_executions) AS int) AS avg_reads,
       CAST(SUM(rs.avg_cpu_time * rs.count_executions) / SUM(rs.count_executions) AS int) AS avg_cpu_us,
       STRING_AGG(CAST(rs.plan_id AS varchar(20)), ',') AS plan_ids
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
GROUP BY i.start_time
ORDER BY i.start_time;
GO
-- 4. The engine noticed it too: a recommendation, even with automatic tuning turned off.
SELECT reason, score,
       JSON_VALUE(state, '$.currentValue') AS state,
       JSON_VALUE(details, '$.implementationDetails.script') AS script
FROM sys.dm_db_tuning_recommendations;

SELECT name, desired_state_desc, actual_state_desc
FROM sys.database_automatic_tuning_options;
