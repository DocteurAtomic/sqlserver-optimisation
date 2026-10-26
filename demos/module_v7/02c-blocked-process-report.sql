-- Module V7, clip 2: the blocked process report. Changes the instance: runs on a throwaway
-- container (or on your own lab, which the last step puts back), with the load running.
-- ci: skip (instance setting, and it needs the load)
-- 1. Sets the blocked process threshold to 2 seconds (an instance setting, 0 by default:
--    no report).
-- 2. Creates and starts the event session blocked_processes, which keeps the reports in a
--    file.
-- 3. Waits a minute, then reads the reports of this run (the file of the session, not the
--    files an earlier run left): how many, then one row per report with the blocked
--    session, the blocking one, the resource and the input buffer of each.
-- 4. Puts the instance back: session dropped, threshold back to 0, advanced options hidden.
--    The .xel files stay in the log folder of the instance.
-- It lasts a little over a minute.
USE master;
GO
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'blocked process threshold (s)', 2;
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
-- Step 3, a minute later. The file of this run is the one the session writes now.
WAITFOR DELAY '00:01:05';
DECLARE @file nvarchar(260) = (
    SELECT CAST(t.target_data AS xml).value('(EventFileTarget/File/@name)[1]', 'nvarchar(260)')
    FROM sys.dm_xe_session_targets AS t
    JOIN sys.dm_xe_sessions AS s ON s.address = t.event_session_address
    WHERE s.name = N'blocked_processes' AND t.target_name = N'event_file');
SELECT timestamp_utc, CAST(event_data AS xml) AS x
INTO #reports
FROM sys.fn_xe_file_target_read_file(@file, NULL, NULL, NULL)
WHERE object_name = N'blocked_process_report';
SELECT COUNT(*) AS reports, MIN(timestamp_utc) AS first_utc, MAX(timestamp_utc) AS last_utc
FROM #reports;
WITH reports AS (SELECT timestamp_utc, x FROM #reports)
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
EXEC sp_configure 'show advanced options', 0;
RECONFIGURE;
GO
