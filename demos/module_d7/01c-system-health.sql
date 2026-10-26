-- Clip D7.1, the morning routine, step 3: what system_health kept of the night. Runs on the
-- lab, in one session, after charge.sh has played the night. Nothing is created:
-- system_health runs on every instance and is only read, in its files (module 5).
-- On a production server, @since_utc is DATEADD(HOUR, -24, SYSUTCDATETIME()); on the lab,
-- the restore of 00-setup.sql.
USE master;
SET NOCOUNT ON;
GO
-- Reading sys.dm_xe_session_targets flushes the buffers of every session to its targets:
-- the events of the last two minutes reach the file (dispatch latency of 120 seconds).
SELECT COUNT(*) AS targets_flushed FROM sys.dm_xe_session_targets;
GO
DECLARE @since_utc datetime2 = (
    SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, SYSDATETIME(), SYSUTCDATETIME()), MAX(restore_date))
    FROM msdb.dbo.restorehistory WHERE destination_database_name = N'PachadataTraining');
SELECT object_name, CAST(event_data AS xml) AS x, timestamp_utc
INTO #night
FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
WHERE timestamp_utc > @since_utc
  AND object_name IN (N'xml_deadlock_report', N'wait_info', N'error_reported');

-- 1. The events of the night that tell about the queries: deadlocks, long waits, serious
--    errors. system_health keeps a wait_info event for a lock wait of more than 30 seconds
--    (15 seconds for a latch or an I/O), written when the wait ends.
SELECT object_name, COUNT(*) AS events, MIN(timestamp_utc) AS first_utc, MAX(timestamp_utc) AS last_utc
FROM #night
GROUP BY object_name;

-- 2. The long waits, grouped by wait type and by statement.
WITH w AS (
    SELECT x.value('(event/data[@name="wait_type"]/text)[1]', 'nvarchar(60)') AS wait_type,
           x.value('(event/data[@name="duration"]/value)[1]', 'bigint') AS duration_ms,
           LEFT(REPLACE(x.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)'),
                        CHAR(10), ' '), 70) AS sql_text
    FROM #night
    WHERE object_name = N'wait_info'
)
SELECT wait_type, COUNT(*) AS waits, MAX(duration_ms) AS max_ms, sql_text
FROM w
GROUP BY wait_type, sql_text
ORDER BY waits DESC;
GO
