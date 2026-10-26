-- Clip 1.2: what a restart erases, and what it no longer erases. Runs on the lab, in one
-- session; reads only. Restart the lab (docker restart sqloptcourse) and run it again to
-- see the first three values move, and the fourth stay.
USE PachadataTraining;
GO
-- Memory of the instance: the plan cache and the waits start with the service.
-- The Query Store lives in the files of the database, and comes back with it.
SELECT i.sqlserver_start_time,
       DATEDIFF(minute, i.sqlserver_start_time, SYSDATETIME()) AS minutes_since_start,
       (SELECT MIN(creation_time) FROM sys.dm_exec_query_stats) AS oldest_plan_in_cache,
       (SELECT MIN(start_time) FROM sys.query_store_runtime_stats_interval) AS oldest_query_store_interval
FROM sys.dm_os_sys_info AS i;
-- The waits since the start of the service, all types together: no history before it.
SELECT COUNT(*) AS wait_types_seen,
       SUM(waiting_tasks_count) AS waits,
       SUM(wait_time_ms) / 1000 AS wait_time_s
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0;
-- The use of the indexes of this database, also counted from the start of the service
-- (or from the last time the database came online).
SELECT OBJECT_SCHEMA_NAME(u.object_id) + N'.' + OBJECT_NAME(u.object_id) AS TableName,
       i.name AS IndexName, u.user_seeks, u.user_scans, u.last_user_scan
FROM sys.dm_db_index_usage_stats AS u
JOIN sys.indexes AS i ON i.object_id = u.object_id AND i.index_id = u.index_id
WHERE u.database_id = DB_ID()
  AND u.object_id = OBJECT_ID(N'Enrollment.Enrollment');
