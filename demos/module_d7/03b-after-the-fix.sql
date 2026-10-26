-- Clip D7.3, the day after the fix, measured. Runs on the lab, in one session, after
-- 03a-the-fix.sql and "charge.sh day". Reads only.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- Step 1. The search of the back office, the last intervals: the forced plan, its calls
-- ended normally and its reads per call. Times in UTC.
SELECT TOP (6) CONVERT(char(5), CAST(i.start_time AS time), 108) AS interval_utc,
       rs.plan_id, p.is_forced_plan, rs.count_executions,
       CAST(rs.avg_logical_io_reads AS int) AS avg_reads,
       CAST(rs.avg_cpu_time AS int) AS avg_cpu_us
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
  AND rs.execution_type = 0
ORDER BY i.start_time DESC, rs.plan_id;
GO
-- Step 2. The payments, interval by interval: completed and aborted executions of the
-- statement that reads the invoice under UPDLOCK, and its lock waits.
SELECT CONVERT(char(5), CAST(i.start_time AS time), 108) AS interval_utc,
       SUM(CASE WHEN rs.execution_type = 0 THEN rs.count_executions ELSE 0 END) AS regular,
       SUM(CASE WHEN rs.execution_type = 3 THEN rs.count_executions ELSE 0 END) AS aborted,
       (SELECT SUM(ws.total_query_wait_time_ms) / 1000
        FROM sys.query_store_wait_stats AS ws
        WHERE ws.runtime_stats_interval_id = i.runtime_stats_interval_id
          AND ws.plan_id IN (SELECT plan_id FROM sys.query_store_plan WHERE query_id = q.query_id)
          AND ws.wait_category_desc = N'Lock') AS lock_wait_s
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
WHERE q.object_id = OBJECT_ID(N'Enrollment.RecordPayment')
  AND qt.query_sql_text LIKE N'%UPDLOCK%'
GROUP BY i.start_time, i.runtime_stats_interval_id, q.query_id
ORDER BY i.start_time;
GO
-- Step 3. The log.
SELECT d.log_reuse_wait_desc,
       CAST(l.total_log_size_in_bytes / 1048576.0 AS decimal(10, 1)) AS log_mb,
       CAST(l.used_log_space_in_percent AS decimal(5, 1)) AS used_pct
FROM sys.databases AS d
CROSS JOIN sys.dm_db_log_space_usage AS l
WHERE d.database_id = DB_ID();
GO
-- Step 4. system_health, read again: the wait of the payments import ended with the KILL,
-- and its wait_info event is now in the file.
SELECT COUNT(*) AS targets_flushed FROM sys.dm_xe_session_targets;
DECLARE @since_utc datetime2 = (
    SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, SYSDATETIME(), SYSUTCDATETIME()), MAX(restore_date))
    FROM msdb.dbo.restorehistory WHERE destination_database_name = DB_NAME());
WITH w AS (
    SELECT timestamp_utc, CAST(event_data AS xml) AS x
    FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
    WHERE timestamp_utc > @since_utc AND object_name = N'wait_info'
)
SELECT timestamp_utc,
       x.value('(event/data[@name="wait_type"]/text)[1]', 'nvarchar(60)') AS wait_type,
       x.value('(event/data[@name="duration"]/value)[1]', 'bigint') / 1000 AS duration_s,
       x.value('(event/action[@name="session_id"]/value)[1]', 'int') AS session_id,
       LEFT(REPLACE(x.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)'),
                    CHAR(10), ' '), 60) AS sql_text
FROM w
ORDER BY timestamp_utc;
GO
