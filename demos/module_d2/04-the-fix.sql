-- Clip D2.4: the fix of the log and of the files. Runs on the lab, in one session, after
-- clip D2.3. The clip then plays 01-io-interval.sql and 03b-offline-online.sql again.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. Shrink the log to its minimum. In the simple recovery model, a checkpoint first
--    truncates it; in the full model, it would be a log backup.
CHECKPOINT;
DBCC SHRINKFILE (PachadataTraining_log, 1) WITH NO_INFOMSGS;
SELECT COUNT(*) AS vlf, CAST(SUM(vlf_size_mb) AS decimal(10, 1)) AS log_mb
FROM sys.dm_db_log_info(DB_ID());
GO
-- 2. Grow it back to its working size in one step, then set fixed growths. The nightly job
--    needs about 1.1 GB of log: 1,536 MB leave room. Growing the log by more than 64 MB
--    writes zeros over the new space: the waits of the session show it.
DROP TABLE IF EXISTS #waits_before;
SELECT wait_type, waiting_tasks_count, wait_time_ms
INTO #waits_before
FROM sys.dm_exec_session_wait_stats
WHERE session_id = @@SPID;
DECLARE @start datetime2 = SYSDATETIME();
ALTER DATABASE PachadataTraining
    MODIFY FILE (NAME = PachadataTraining_log, SIZE = 1536MB, FILEGROWTH = 512MB);
SELECT DATEDIFF(MILLISECOND, @start, SYSDATETIME()) AS log_growth_ms;
SELECT w.wait_type,
       w.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) AS waits,
       w.wait_time_ms - ISNULL(b.wait_time_ms, 0) AS wait_ms
FROM sys.dm_exec_session_wait_stats AS w
LEFT JOIN #waits_before AS b ON b.wait_type = w.wait_type
WHERE w.session_id = @@SPID
  AND w.wait_type LIKE N'PREEMPTIVE_OS_%'
  AND w.waiting_tasks_count > ISNULL(b.waiting_tasks_count, 0)
ORDER BY wait_ms DESC;
ALTER DATABASE PachadataTraining
    MODIFY FILE (NAME = PachadataTraining, FILEGROWTH = 256MB);
GO
-- 3. The result.
SELECT name, type_desc, size / 128 AS size_mb,
       CASE WHEN is_percent_growth = 1 THEN CONCAT(growth, ' %')
            ELSE CONCAT(growth / 128, ' MB') END AS growth
FROM sys.database_files;
SELECT COUNT(*) AS vlf, CAST(MIN(vlf_size_mb) AS decimal(10, 1)) AS smallest_mb,
       CAST(MAX(vlf_size_mb) AS decimal(10, 1)) AS largest_mb
FROM sys.dm_db_log_info(DB_ID());
GO
