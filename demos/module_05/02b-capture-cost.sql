-- Clip 5.2: what a capture costs, measured on a loop that does nothing but fire
-- sql_statement_completed, the worst case. Runs on the lab, in one session, alone (stop
-- charge.sh first: the load would blur the measure). Three sessions are created, measured,
-- stopped and dropped one after the other; nothing is left at the end. The processor
-- times vary from one run to the other: the order of magnitude is what counts.
USE PachadataTraining;
GO
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'tempdb..#cost') IS NOT NULL DROP TABLE #cost;
CREATE TABLE #cost (step varchar(40) NOT NULL, run int NOT NULL, cpu_ms int NOT NULL);
GO
-- The loop: 100,000 turns of a WHILE in a batch. The test of the WHILE and the SET each
-- fire sql_statement_completed: 200,000 events per run (counted with an event_counter).
-- Its processor time is read in sys.dm_exec_requests before and after, inside the same
-- batch. GO 3 runs the batch three times.
-- 1. No session listens to the event.
DECLARE @step varchar(40) = '1. no session';
DECLARE @cpu0 int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID);
DECLARE @i int = 0;
WHILE @i < 100000 SET @i += 1;
INSERT INTO #cost (step, run, cpu_ms)
SELECT @step, (SELECT COUNT(*) + 1 FROM #cost WHERE step = @step), cpu_time - @cpu0
FROM sys.dm_exec_requests WHERE session_id = @@SPID;
GO 3
-- 2. A session listens, and its predicate rejects every event (none lasts 5 seconds),
--    the database tested first.
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'CostProbe')
    DROP EVENT SESSION CostProbe ON SERVER;
GO
CREATE EVENT SESSION CostProbe ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
    WHERE sqlserver.database_name = N'PachadataTraining'
      AND duration > 5000000
)
ADD TARGET package0.ring_buffer
WITH (STARTUP_STATE = OFF);
GO
ALTER EVENT SESSION CostProbe ON SERVER STATE = START;
GO
DECLARE @step varchar(40) = '2. predicate rejects all';
DECLARE @cpu0 int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID);
DECLARE @i int = 0;
WHILE @i < 100000 SET @i += 1;
INSERT INTO #cost (step, run, cpu_ms)
SELECT @step, (SELECT COUNT(*) + 1 FROM #cost WHERE step = @step), cpu_time - @cpu0
FROM sys.dm_exec_requests WHERE session_id = @@SPID;
GO 3
ALTER EVENT SESSION CostProbe ON SERVER STATE = STOP;
DROP EVENT SESSION CostProbe ON SERVER;
GO
-- 2b. The same predicate, its conditions swapped: the integer test on a field of the
--     event first. The evaluation stops at the first false condition.
CREATE EVENT SESSION CostProbe ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
    WHERE duration > 5000000
      AND sqlserver.database_name = N'PachadataTraining'
)
ADD TARGET package0.ring_buffer
WITH (STARTUP_STATE = OFF);
GO
ALTER EVENT SESSION CostProbe ON SERVER STATE = START;
GO
DECLARE @step varchar(40) = '2b. duration tested first';
DECLARE @cpu0 int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID);
DECLARE @i int = 0;
WHILE @i < 100000 SET @i += 1;
INSERT INTO #cost (step, run, cpu_ms)
SELECT @step, (SELECT COUNT(*) + 1 FROM #cost WHERE step = @step), cpu_time - @cpu0
FROM sys.dm_exec_requests WHERE session_id = @@SPID;
GO 3
ALTER EVENT SESSION CostProbe ON SERVER STATE = STOP;
DROP EVENT SESSION CostProbe ON SERVER;
GO
-- 2c. And without the text of the statement, an optional field collected by default and
--     copied before the predicate.
CREATE EVENT SESSION CostProbe ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
    SET collect_statement = 0
    WHERE duration > 5000000
      AND sqlserver.database_name = N'PachadataTraining'
)
ADD TARGET package0.ring_buffer
WITH (STARTUP_STATE = OFF);
GO
ALTER EVENT SESSION CostProbe ON SERVER STATE = START;
GO
DECLARE @step varchar(40) = '2c. no statement text';
DECLARE @cpu0 int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID);
DECLARE @i int = 0;
WHILE @i < 100000 SET @i += 1;
INSERT INTO #cost (step, run, cpu_ms)
SELECT @step, (SELECT COUNT(*) + 1 FROM #cost WHERE step = @step), cpu_time - @cpu0
FROM sys.dm_exec_requests WHERE session_id = @@SPID;
GO 3
ALTER EVENT SESSION CostProbe ON SERVER STATE = STOP;
DROP EVENT SESSION CostProbe ON SERVER;
GO
-- 3. A session keeps every event, with the sql_text action, in a ring_buffer.
CREATE EVENT SESSION CostProbe ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
    ACTION (sqlserver.sql_text)
    WHERE sqlserver.database_name = N'PachadataTraining'
)
ADD TARGET package0.ring_buffer (SET max_events_limit = 1000)
WITH (STARTUP_STATE = OFF);
GO
ALTER EVENT SESSION CostProbe ON SERVER STATE = START;
GO
DECLARE @step varchar(40) = '3. all kept, sql_text';
DECLARE @cpu0 int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID);
DECLARE @i int = 0;
WHILE @i < 100000 SET @i += 1;
INSERT INTO #cost (step, run, cpu_ms)
SELECT @step, (SELECT COUNT(*) + 1 FROM #cost WHERE step = @step), cpu_time - @cpu0
FROM sys.dm_exec_requests WHERE session_id = @@SPID;
GO 3
ALTER EVENT SESSION CostProbe ON SERVER STATE = STOP;
DROP EVENT SESSION CostProbe ON SERVER;
GO
-- 4. Losses: the same events into a file, through a session of 256 KB of memory that may
--    drop events rather than slow the load (ALLOW_SINGLE_EVENT_LOSS, the default).
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'LossProbe')
    DROP EVENT SESSION LossProbe ON SERVER;
GO
CREATE EVENT SESSION LossProbe ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
    ACTION (sqlserver.sql_text)
    WHERE sqlserver.database_name = N'PachadataTraining'
)
ADD TARGET package0.event_file (SET filename = N'LossProbe.xel', max_file_size = 20,
                                    max_rollover_files = 1)
WITH (MAX_MEMORY = 256 KB, EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
      STARTUP_STATE = OFF);
GO
ALTER EVENT SESSION LossProbe ON SERVER STATE = START;
GO
DECLARE @step varchar(40) = '4. file, 256 KB';
DECLARE @cpu0 int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID);
DECLARE @i int = 0;
WHILE @i < 100000 SET @i += 1;
INSERT INTO #cost (step, run, cpu_ms)
SELECT @step, (SELECT COUNT(*) + 1 FROM #cost WHERE step = @step), cpu_time - @cpu0
FROM sys.dm_exec_requests WHERE session_id = @@SPID;
GO
SELECT name, total_regular_buffers, regular_buffer_size / 1024 AS buffer_kb,
       dropped_event_count, dropped_buffer_count
FROM sys.dm_xe_sessions
WHERE name = N'LossProbe';
GO
ALTER EVENT SESSION LossProbe ON SERVER STATE = STOP;
DROP EVENT SESSION LossProbe ON SERVER;
GO
-- 5. The measures: processor time of the loop, and per event.
SELECT step, MIN(cpu_ms) AS min_cpu_ms, MAX(cpu_ms) AS max_cpu_ms,
       CAST(MIN(cpu_ms) * 1000.0 / 200000 AS decimal(6, 2)) AS min_us_per_event
FROM #cost
GROUP BY step
ORDER BY step;
DROP TABLE #cost;
GO
