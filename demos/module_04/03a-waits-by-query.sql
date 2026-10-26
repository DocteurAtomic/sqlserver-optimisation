-- Clip 4.3: the waits of each plan, kept by Query Store since SQL Server 2017. Runs on the
-- lab, in one session, after 00-setup.sql. Times in milliseconds.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- Duration, CPU and waits of each plan of the query, over all its intervals.
WITH runtime AS (
    SELECT rs.plan_id,
           SUM(rs.count_executions) AS executions,
           SUM(rs.avg_duration * rs.count_executions) / 1000 AS total_duration_ms,
           SUM(rs.avg_cpu_time * rs.count_executions) / 1000 AS total_cpu_ms
    FROM sys.query_store_runtime_stats AS rs
    GROUP BY rs.plan_id
), waits AS (
    SELECT ws.plan_id, SUM(ws.total_query_wait_time_ms) AS total_wait_ms
    FROM sys.query_store_wait_stats AS ws
    GROUP BY ws.plan_id
)
SELECT r.plan_id, r.executions,
       CAST(r.total_duration_ms AS int) AS total_duration_ms,
       CAST(r.total_cpu_ms AS int) AS total_cpu_ms,
       ISNULL(w.total_wait_ms, 0) AS total_wait_ms
FROM runtime AS r
JOIN sys.query_store_plan AS p ON p.plan_id = r.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
LEFT JOIN waits AS w ON w.plan_id = r.plan_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
ORDER BY r.plan_id;
GO
-- The same waits by category: Query Store groups the wait types, it does not keep them
-- one by one as sys.dm_os_wait_stats does.
SELECT ws.plan_id, ws.wait_category_desc,
       SUM(ws.total_query_wait_time_ms) AS total_wait_ms,
       CAST(AVG(ws.avg_query_wait_time_ms) AS decimal(10, 3)) AS avg_wait_ms
FROM sys.query_store_wait_stats AS ws
JOIN sys.query_store_plan AS p ON p.plan_id = ws.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
GROUP BY ws.plan_id, ws.wait_category_desc
ORDER BY ws.plan_id, total_wait_ms DESC;
