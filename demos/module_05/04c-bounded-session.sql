-- Clip 5.4: a session that stops by itself, with MAX_DURATION (SQL Server 2025). Runs on the
-- lab, in one session, alone or with charge.sh; it lasts a little more than a minute, and
-- drops the session at the end. On SQL Server 2022 and before, MAX_DURATION does not exist:
-- a job of the Agent has to stop the session.
USE master;
GO
SET NOCOUNT ON;
GO
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'DeadlockWatch')
    DROP EVENT SESSION DeadlockWatch ON SERVER;
GO
-- The deadlock victims of the database, for one minute.
CREATE EVENT SESSION DeadlockWatch ON SERVER
ADD EVENT sqlserver.error_reported (
    ACTION (sqlserver.client_hostname, sqlserver.sql_text)
    WHERE sqlserver.database_name = N'PachadataTraining'
      AND error_number = 1205
)
ADD TARGET package0.ring_buffer
WITH (MAX_DURATION = 1 MINUTES, STARTUP_STATE = OFF);
GO
ALTER EVENT SESSION DeadlockWatch ON SERVER STATE = START;
GO
-- The definition, with its duration in seconds (0 means unlimited), and the running session.
SELECT ss.name, ss.max_duration, ss.startup_state,
       CASE WHEN s.name IS NULL THEN 'stopped' ELSE 'running' END AS state
FROM sys.server_event_sessions AS ss
LEFT JOIN sys.dm_xe_sessions AS s ON s.name = ss.name
WHERE ss.name IN (N'DeadlockWatch', N'system_health')
ORDER BY ss.name;
GO
WAITFOR DELAY '00:01:10';
GO
-- Seventy seconds later: the session has stopped by itself, its definition stays.
SELECT ss.name, ss.max_duration,
       CASE WHEN s.name IS NULL THEN 'stopped' ELSE 'running' END AS state
FROM sys.server_event_sessions AS ss
LEFT JOIN sys.dm_xe_sessions AS s ON s.name = ss.name
WHERE ss.name = N'DeadlockWatch';
GO
DROP EVENT SESSION DeadlockWatch ON SERVER;
GO
