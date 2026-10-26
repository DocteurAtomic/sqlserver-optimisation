-- ci: skip (captures the statements of the load: start ./demos/module_05/charge.sh first)
-- Clip 5.2: the statements of the database that last more than 100 ms, written to a file,
-- read back with sys.fn_xe_file_target_read_file and grouped by query_hash. Runs on the
-- lab, in one session, while charge.sh runs. The session is dropped at the end; its .xel
-- files stay in the log folder of the instance (/var/opt/mssql/log in the container).
USE master;
GO
SET NOCOUNT ON;
GO
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'SlowStatements')
    DROP EVENT SESSION SlowStatements ON SERVER;
GO
-- sql_statement_completed: the statements of the batches sent by the clients.
-- sp_statement_completed: the statements inside the procedures, which the first event
-- does not see. duration is in microseconds: 100000 is 100 ms.
CREATE EVENT SESSION SlowStatements ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
    ACTION (sqlserver.client_hostname, sqlserver.query_hash_signed)
    WHERE sqlserver.database_name = N'PachadataTraining'
      AND duration > 100000
),
ADD EVENT sqlserver.sp_statement_completed (
    SET collect_object_name = 1   -- an optional field, off by default: the procedure name
    ACTION (sqlserver.client_hostname, sqlserver.query_hash_signed)
    WHERE sqlserver.database_name = N'PachadataTraining'
      AND duration > 100000
)
ADD TARGET package0.event_file (
    SET filename = N'SlowStatements.xel', max_file_size = 50, max_rollover_files = 2
)
WITH (MAX_MEMORY = 4096 KB,
      EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
      MAX_DISPATCH_LATENCY = 5 SECONDS,
      STARTUP_STATE = OFF);
GO
ALTER EVENT SESSION SlowStatements ON SERVER STATE = START;
GO
-- One minute of the load, then the time for the buffers to reach the file.
WAITFOR DELAY '00:01:00';
GO
-- The .xel files outlive the session: a file of an earlier run of this script is still in
-- the folder, and the star would read it too. Only the events written since the session
-- started are kept (create_time is local time, timestamp_utc is UTC).
DECLARE @start_utc datetime2 = (
    SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, SYSDATETIME(), SYSUTCDATETIME()), create_time)
    FROM sys.dm_xe_sessions
    WHERE name = N'SlowStatements');

-- 1. The events of the file, one row each, the longest first. The star gathers the
--    rollover files. What the session asked by ACTION is read under action, the fields of
--    the event under data.
WITH events AS (
    SELECT object_name AS event_name, timestamp_utc, CAST(event_data AS xml) AS x
    FROM sys.fn_xe_file_target_read_file(N'SlowStatements*.xel', NULL, NULL, NULL)
    WHERE timestamp_utc >= @start_utc
)
SELECT TOP (8)
       event_name,
       x.value('(event/data[@name="duration"]/value)[1]', 'bigint') / 1000 AS duration_ms,
       x.value('(event/data[@name="cpu_time"]/value)[1]', 'bigint') / 1000 AS cpu_ms,
       x.value('(event/data[@name="logical_reads"]/value)[1]', 'bigint') AS reads,
       x.value('(event/action[@name="client_hostname"]/value)[1]', 'nvarchar(128)') AS host,
       x.value('(event/data[@name="object_name"]/value)[1]', 'nvarchar(128)') AS module,
       LEFT(REPLACE(REPLACE(x.value('(event/data[@name="statement"]/value)[1]', 'nvarchar(max)'),
                            CHAR(13), N' '), CHAR(10), N' '), 50) AS statement
FROM events
ORDER BY duration_ms DESC;

-- 2. Grouped by query_hash: one row per shape of statement, whatever its literal values.
--    EXEC, WAITFOR, SET and the other statements that have no plan of their own have a
--    query_hash of zero: those are grouped by the start of their text instead.
WITH events AS (
    SELECT CAST(event_data AS xml) AS x
    FROM sys.fn_xe_file_target_read_file(N'SlowStatements*.xel', NULL, NULL, NULL)
    WHERE timestamp_utc >= @start_utc
), rows AS (
    SELECT CAST(x.value('(event/action[@name="query_hash_signed"]/value)[1]', 'bigint')
                AS binary(8)) AS query_hash,
           x.value('(event/data[@name="duration"]/value)[1]', 'bigint') / 1000 AS duration_ms,
           x.value('(event/data[@name="object_name"]/value)[1]', 'nvarchar(128)') AS module,
           x.value('(event/action[@name="client_hostname"]/value)[1]', 'nvarchar(128)') AS host,
           LEFT(LTRIM(REPLACE(REPLACE(x.value('(event/data[@name="statement"]/value)[1]', 'nvarchar(max)'),
                                      CHAR(13), N' '), CHAR(10), N' ')), 30) AS statement
    FROM events
)
SELECT query_hash, MIN(host) AS host, ISNULL(MIN(module), N'') AS module, MIN(statement) AS statement,
       COUNT(*) AS executions, AVG(duration_ms) AS avg_ms, MAX(duration_ms) AS max_ms
FROM rows
GROUP BY query_hash, CASE WHEN query_hash = 0x0000000000000000 THEN statement END
ORDER BY SUM(duration_ms) DESC;

-- 3. Did the session lose events?
SELECT name, dropped_event_count, dropped_buffer_count, total_buffer_size / 1024 AS buffer_kb
FROM sys.dm_xe_sessions
WHERE name = N'SlowStatements';
GO
ALTER EVENT SESSION SlowStatements ON SERVER STATE = STOP;
DROP EVENT SESSION SlowStatements ON SERVER;
GO
