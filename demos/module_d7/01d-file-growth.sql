-- Clip D7.1, the morning routine, step 4: the files of the database. Runs on the lab, in one
-- session, after charge.sh has played the night. Reads only.
-- On a production server, @since is DATEADD(HOUR, -24, GETDATE()); on the lab, the restore
-- of 00-setup.sql.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The automatic growths since the evening, as the default trace recorded them (module
--    D2): event 92 for a data file, 93 for a log file. IntegerData is in 8 KB pages,
--    Duration in microseconds.
DECLARE @trace nvarchar(260) = (
    SELECT CASE WHEN path LIKE N'%log[_]%.trc'
                THEN LEFT(path, LEN(path) - CHARINDEX(N'_', REVERSE(path))) + N'.trc'
                ELSE path END
    FROM sys.traces WHERE is_default = 1);
DECLARE @since datetime = (SELECT MAX(restore_date) FROM msdb.dbo.restorehistory
                           WHERE destination_database_name = DB_NAME());
SELECT te.name AS event_name, t.FileName,
       COUNT(*) AS growths,
       SUM(t.IntegerData) / 128 AS added_mb,
       MIN(t.StartTime) AS first_growth, MAX(t.StartTime) AS last_growth,
       SUM(t.Duration) / 1000 AS total_ms
FROM sys.fn_trace_gettable(@trace, DEFAULT) AS t
JOIN sys.trace_events AS te ON te.trace_event_id = t.EventClass
WHERE t.EventClass IN (92, 93)
  AND t.DatabaseName = DB_NAME()
  AND t.StartTime >= @since
GROUP BY te.name, t.FileName;
GO
-- 2. The files now, and the log: its size, the part in use, and what keeps it from being
--    reused. In SIMPLE recovery, a checkpoint truncates the log up to the oldest active
--    transaction: ACTIVE_TRANSACTION means that one is still open.
SELECT name, type_desc, size / 128 AS size_mb, FILEPROPERTY(name, 'SpaceUsed') / 128 AS used_mb
FROM sys.database_files;
SELECT d.recovery_model_desc, d.log_reuse_wait_desc,
       CAST(l.total_log_size_in_bytes / 1048576.0 AS decimal(10, 1)) AS log_mb,
       CAST(l.used_log_space_in_percent AS decimal(5, 1)) AS used_pct
FROM sys.databases AS d
CROSS JOIN sys.dm_db_log_space_usage AS l
WHERE d.database_id = DB_ID();
GO
