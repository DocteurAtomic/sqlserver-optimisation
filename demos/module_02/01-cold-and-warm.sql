-- Clip 2.1: the same query read cold, then warm. Lab only: the database is taken offline
-- and back online, which empties its pages from the buffer pool (and its plans from the
-- cache). Messages of STATISTICS IO and TIME are in the Messages tab of SSMS.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- The table read by the query: a heap of 7.8 million rows.
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS TableName,
       index_id, row_count, used_page_count,
       used_page_count * 8 / 1024 AS used_mb
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'Elearning.Activity') AND index_id = 0;
GO
-- Cold cache for this database only. On your own lab, CHECKPOINT then
-- DBCC DROPCLEANBUFFERS empties the cache of the whole instance: never on a production server.
USE master;
ALTER DATABASE PachadataTraining SET OFFLINE WITH ROLLBACK IMMEDIATE;
ALTER DATABASE PachadataTraining SET ONLINE;
GO
USE PachadataTraining;
SET NOCOUNT ON;
SELECT COUNT(*) AS PagesInCache
FROM sys.dm_os_buffer_descriptors
WHERE database_id = DB_ID();
GO
-- The events of the first quarter, as the e-learning dashboard shows them.
-- First run: cold.
SELECT wait_type, waiting_tasks_count, wait_time_ms
INTO #WaitsBefore
FROM sys.dm_exec_session_wait_stats
WHERE session_id = @@SPID;

SET STATISTICS IO, TIME ON;
SELECT COUNT(*) AS Events, SUM(CAST(DurationSeconds AS bigint)) AS Seconds
FROM Elearning.Activity
WHERE EventTime >= '20260101' AND EventTime < '20260401';
SET STATISTICS IO, TIME OFF;

-- What the session waited for during the cold run, reads from disk included.
SELECT w.wait_type,
       w.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) AS waits,
       w.wait_time_ms - ISNULL(b.wait_time_ms, 0) AS wait_ms
FROM sys.dm_exec_session_wait_stats AS w
LEFT JOIN #WaitsBefore AS b ON b.wait_type = w.wait_type
WHERE w.session_id = @@SPID AND w.wait_type LIKE N'PAGEIOLATCH%';
GO
-- Second run: warm, the pages are in the cache.
SET STATISTICS IO, TIME ON;
SELECT COUNT(*) AS Events, SUM(CAST(DurationSeconds AS bigint)) AS Seconds
FROM Elearning.Activity
WHERE EventTime >= '20260101' AND EventTime < '20260401';
SET STATISTICS IO, TIME OFF;
GO
-- What is now in the cache for this database, by object.
SELECT TOP (5)
       OBJECT_SCHEMA_NAME(p.object_id) + N'.' + OBJECT_NAME(p.object_id) AS ObjectName,
       COUNT(*) AS PagesInCache,
       COUNT(*) * 8 / 1024 AS CacheMb
FROM sys.dm_os_buffer_descriptors AS b
JOIN sys.allocation_units AS a ON a.allocation_unit_id = b.allocation_unit_id
JOIN sys.partitions AS p ON p.hobt_id = a.container_id
WHERE b.database_id = DB_ID()
GROUP BY p.object_id
ORDER BY PagesInCache DESC;
