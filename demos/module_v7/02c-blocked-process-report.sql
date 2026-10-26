-- Module V7, clip 2: the blocked process report. Changes the instance: runs on a throwaway
-- container (or on your own lab, which the last step puts back), with the load running.
-- ci: skip (instance setting, and it needs the load)
-- 1. Sets the blocked process threshold to 5 seconds (an instance setting, 0 by default:
--    no report).
-- 2. Creates and starts the event session blocked_processes, which keeps the reports in a
--    file.
-- 3. After a minute of load, reads the reports: the blocked session, the blocking one, and
--    the input buffer of each.
-- 4. Puts the instance back: session dropped, threshold back to 0.
USE master;
GO
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'blocked process threshold (s)', 5;
RECONFIGURE;
GO
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'blocked_processes')
    DROP EVENT SESSION blocked_processes ON SERVER;
GO
CREATE EVENT SESSION blocked_processes ON SERVER
ADD EVENT sqlserver.blocked_process_report (
    WHERE (database_name = N'PachadataTraining'))
ADD TARGET package0.event_file (SET filename = N'blocked_processes.xel', max_file_size = 20)
WITH (MAX_DISPATCH_LATENCY = 5 SECONDS);
GO
ALTER EVENT SESSION blocked_processes ON SERVER STATE = START;
GO
-- Step 3, a minute later: one row per report.
WITH reports AS (
    SELECT timestamp_utc, CAST(event_data AS xml) AS x
    FROM sys.fn_xe_file_target_read_file(N'blocked_processes*.xel', NULL, NULL, NULL)
    WHERE object_name = N'blocked_process_report'
)
SELECT timestamp_utc,
       x.value('(event/data[@name="duration"]/value)[1]', 'bigint') / 1000 AS blocked_ms,
       x.value('(//blocked-process/process/@spid)[1]', 'int') AS blocked_spid,
       x.value('(//blocked-process/process/@hostname)[1]', 'nvarchar(128)') AS blocked_host,
       x.value('(//blocked-process/process/@waitresource)[1]', 'nvarchar(100)') AS wait_resource,
       LEFT(LTRIM(x.value('(//blocked-process/process/inputbuf)[1]', 'nvarchar(max)')), 60) AS blocked_input,
       x.value('(//blocking-process/process/@spid)[1]', 'int') AS blocking_spid,
       x.value('(//blocking-process/process/@hostname)[1]', 'nvarchar(128)') AS blocking_host,
       LEFT(LTRIM(x.value('(//blocking-process/process/inputbuf)[1]', 'nvarchar(max)')), 60) AS blocking_input
FROM reports
ORDER BY timestamp_utc DESC;
GO
-- Step 4. The instance as it was.
ALTER EVENT SESSION blocked_processes ON SERVER STATE = STOP;
DROP EVENT SESSION blocked_processes ON SERVER;
EXEC sp_configure 'blocked process threshold (s)', 0;
RECONFIGURE;
GO
