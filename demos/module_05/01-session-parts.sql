-- ci: skip (reads the errors of the load: start ./demos/module_05/charge.sh first)
-- Clip 5.1: the four parts of a session (event, action, predicate, target), on the
-- complaint of the planning team. Runs on the lab, in one session, while charge.sh runs.
-- The session it creates is stopped and dropped at the end.
USE master;
GO
SET NOCOUNT ON;
GO
-- 1. What each tracing system can capture on this instance.
SELECT (SELECT COUNT(*) FROM sys.trace_events) AS sql_trace_events,
       (SELECT COUNT(*) FROM sys.dm_xe_objects WHERE object_type = 'event') AS xe_events,
       (SELECT COUNT(*) FROM sys.dm_xe_objects WHERE object_type = 'action') AS xe_actions,
       (SELECT COUNT(*) FROM sys.dm_xe_objects WHERE object_type = 'target') AS xe_targets;

-- 2. An event to listen to: the errors sent to the clients.
SELECT p.name AS package, o.name AS event_name, o.description
FROM sys.dm_xe_objects AS o
JOIN sys.dm_xe_packages AS p ON p.guid = o.package_guid
WHERE o.object_type = 'event' AND o.name = 'error_reported' AND p.name = 'sqlserver';

-- 3. The fields the event gives without asking: they can go in the predicate.
SELECT name, type_name
FROM sys.dm_xe_object_columns
WHERE object_name = 'error_reported' AND column_type = 'data'
  AND name IN ('error_number', 'severity', 'message', 'is_intercepted');
GO
-- 4. The session: every error of severity 11 or more in the database, with three actions,
--    kept in memory by a ring_buffer. STARTUP_STATE = OFF: it will not restart with the
--    instance.
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'PlanningErrors')
    DROP EVENT SESSION PlanningErrors ON SERVER;
GO
CREATE EVENT SESSION PlanningErrors ON SERVER
ADD EVENT sqlserver.error_reported (
    ACTION (sqlserver.client_hostname, sqlserver.session_id, sqlserver.sql_text)
    WHERE sqlserver.database_name = N'PachadataTraining'
      AND severity >= 11
)
ADD TARGET package0.ring_buffer (SET max_events_limit = 1000)
WITH (MAX_DISPATCH_LATENCY = 5 SECONDS, STARTUP_STATE = OFF);
GO
ALTER EVENT SESSION PlanningErrors ON SERVER STATE = START;
GO
SELECT s.name, s.create_time, t.target_name
FROM sys.dm_xe_sessions AS s
JOIN sys.dm_xe_session_targets AS t ON t.event_session_address = s.address
WHERE s.name = N'PlanningErrors';
GO
-- 5. One minute of the load.
WAITFOR DELAY '00:01:00';
GO
-- 6. What the ring_buffer kept: the XML is copied once into a variable, then read.
DECLARE @x xml = (
    SELECT CAST(t.target_data AS xml)
    FROM sys.dm_xe_sessions AS s
    JOIN sys.dm_xe_session_targets AS t ON t.event_session_address = s.address
    WHERE s.name = N'PlanningErrors' AND t.target_name = N'ring_buffer');

SELECT error_number, severity, host, batch, COUNT(*) AS errors
FROM (
    SELECT e.n.value('(data[@name="error_number"]/value)[1]', 'int') AS error_number,
           e.n.value('(data[@name="severity"]/value)[1]', 'int') AS severity,
           e.n.value('(action[@name="client_hostname"]/value)[1]', 'nvarchar(128)') AS host,
           -- the batch, up to its first comma: the procedure and the session it moves
           LEFT(e.n.value('(action[@name="sql_text"]/value)[1]', 'nvarchar(max)'),
                CHARINDEX(N',', e.n.value('(action[@name="sql_text"]/value)[1]', 'nvarchar(max)')
                          + N',') - 1) AS batch
    FROM @x.nodes('/RingBufferTarget/event') AS e(n)
) AS errors
GROUP BY error_number, severity, host, batch
ORDER BY errors DESC;

-- The message of the last one.
SELECT TOP (1)
       e.n.value('@timestamp', 'datetime2(3)') AS timestamp_utc,
       e.n.value('(data[@name="message"]/value)[1]', 'nvarchar(400)') AS message
FROM @x.nodes('/RingBufferTarget/event') AS e(n)
ORDER BY timestamp_utc DESC;
GO
-- 7. A diagnostic session does not outlive the investigation: stop it, drop it. The
--    content of a ring_buffer is lost when the session stops.
ALTER EVENT SESSION PlanningErrors ON SERVER STATE = STOP;
DROP EVENT SESSION PlanningErrors ON SERVER;
GO
