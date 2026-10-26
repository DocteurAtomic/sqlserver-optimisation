-- Module 5 exercise, part 1: solution. Runs on the lab, in one session, after 1-start.sql.
-- Two sessions: ExerciseLong writes to a file the statements of more than 100 ms,
-- ExerciseByHash counts the executions per query_hash in a histogram target and keeps the
-- events in a ring_buffer. The load dbo.ExerciseWorkload runs, the targets are read, and the
-- sessions are dropped at the end. The .xel files stay in the log folder of the instance.
USE master;
GO
SET NOCOUNT ON;
GO
-- 1. The long statements. sp_statement_completed is needed: the statements of a procedure,
--    and the dynamic SQL it runs, do not fire sql_statement_completed.
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'ExerciseLong')
    DROP EVENT SESSION ExerciseLong ON SERVER;
GO
CREATE EVENT SESSION ExerciseLong ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
    ACTION (sqlserver.query_hash_signed)
    WHERE sqlserver.database_name = N'PachadataTraining'
      AND duration > 100000
),
ADD EVENT sqlserver.sp_statement_completed (
    ACTION (sqlserver.query_hash_signed)
    WHERE sqlserver.database_name = N'PachadataTraining'
      AND duration > 100000
)
ADD TARGET package0.event_file (
    SET filename = N'ExerciseLong.xel', max_file_size = 20, max_rollover_files = 2
)
WITH (MAX_DISPATCH_LATENCY = 5 SECONDS, MAX_DURATION = 1 HOURS, STARTUP_STATE = OFF);
GO
-- 2. The executions per shape of statement: a histogram target on the action
--    query_hash_signed (source_type = 1 for an action), and a ring_buffer that keeps the
--    events themselves. The control statements (SET, WHILE, EXEC) have a query_hash of zero:
--    the predicate leaves them out.
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = N'ExerciseByHash')
    DROP EVENT SESSION ExerciseByHash ON SERVER;
GO
CREATE EVENT SESSION ExerciseByHash ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
    ACTION (sqlserver.query_hash_signed)
    WHERE sqlserver.database_name = N'PachadataTraining'
      AND sqlserver.query_hash_signed <> 0
),
ADD EVENT sqlserver.sp_statement_completed (
    ACTION (sqlserver.query_hash_signed)
    WHERE sqlserver.database_name = N'PachadataTraining'
      AND sqlserver.query_hash_signed <> 0
)
ADD TARGET package0.histogram (
    SET source = N'sqlserver.query_hash_signed', source_type = 1, slots = 1024
),
ADD TARGET package0.ring_buffer (SET max_memory = 2048, max_events_limit = 1000)
WITH (MAX_DISPATCH_LATENCY = 1 SECONDS, MAX_DURATION = 1 HOURS, STARTUP_STATE = OFF);
GO
ALTER EVENT SESSION ExerciseLong ON SERVER STATE = START;
ALTER EVENT SESSION ExerciseByHash ON SERVER STATE = START;
GO
-- 3. The load.
USE PachadataTraining;
GO
EXEC dbo.ExerciseWorkload;
GO
USE master;                 -- the wait below must not be captured
WAITFOR DELAY '00:00:06';   -- longer than MAX_DISPATCH_LATENCY
GO
-- 4. The long statements, the most reads first; only the events of this run (the .xel
--    files of an earlier run are still in the folder).
DECLARE @start_utc datetime2 = (
    SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, SYSDATETIME(), SYSUTCDATETIME()), create_time)
    FROM sys.dm_xe_sessions
    WHERE name = N'ExerciseLong');
WITH events AS (
    SELECT object_name AS event_name, CAST(event_data AS xml) AS x
    FROM sys.fn_xe_file_target_read_file(N'ExerciseLong*.xel', NULL, NULL, NULL)
    WHERE timestamp_utc >= @start_utc
)
SELECT event_name,
       x.value('(event/data[@name="duration"]/value)[1]', 'bigint') / 1000 AS duration_ms,
       x.value('(event/data[@name="cpu_time"]/value)[1]', 'bigint') / 1000 AS cpu_ms,
       x.value('(event/data[@name="logical_reads"]/value)[1]', 'bigint') AS reads,
       CAST(x.value('(event/action[@name="query_hash_signed"]/value)[1]', 'bigint') AS binary(8))
           AS query_hash,
       LEFT(LTRIM(REPLACE(REPLACE(x.value('(event/data[@name="statement"]/value)[1]', 'nvarchar(max)'),
                                  CHAR(13), N' '), CHAR(10), N' ')), 50) AS statement
FROM events
ORDER BY reads DESC;
GO
-- 5. The most frequent shapes: the histogram, one counter per query_hash. Its XML is copied
--    into a variable first, then read.
DECLARE @histogram xml = (
    SELECT CAST(t.target_data AS xml)
    FROM sys.dm_xe_sessions AS s
    JOIN sys.dm_xe_session_targets AS t ON t.event_session_address = s.address
    WHERE s.name = N'ExerciseByHash' AND t.target_name = N'histogram');
SELECT CAST(h.slot.value('(value)[1]', 'bigint') AS binary(8)) AS query_hash,
       h.slot.value('@count', 'bigint') AS executions
FROM @histogram.nodes('/HistogramTarget/Slot') AS h(slot)
ORDER BY executions DESC;
GO
-- 6. The events of the ring_buffer, grouped by text, then by shape.
DECLARE @events xml = (
    SELECT CAST(t.target_data AS xml)
    FROM sys.dm_xe_sessions AS s
    JOIN sys.dm_xe_session_targets AS t ON t.event_session_address = s.address
    WHERE s.name = N'ExerciseByHash' AND t.target_name = N'ring_buffer');
SELECT CAST(e.n.value('(action[@name="query_hash_signed"]/value)[1]', 'bigint') AS binary(8))
           AS query_hash,
       e.n.value('(data[@name="duration"]/value)[1]', 'bigint') AS duration_us,
       e.n.value('(data[@name="statement"]/value)[1]', 'nvarchar(400)') AS statement
INTO #events
FROM @events.nodes('/RingBufferTarget/event') AS e(n);

-- By text: each concatenated lookup is a text of its own, executed once.
SELECT TOP (5) COUNT(*) AS executions, LEFT(statement, 80) AS statement
FROM #events
GROUP BY statement
ORDER BY executions DESC;

-- By shape: one row per query_hash, with the number of distinct texts.
SELECT query_hash, COUNT(*) AS executions, COUNT(DISTINCT statement) AS texts,
       AVG(duration_us) AS avg_us, MAX(duration_us) AS max_us,
       LEFT(MIN(statement), 70) AS example
FROM #events
GROUP BY query_hash
ORDER BY executions DESC;
DROP TABLE #events;
GO
-- 7. Stop and drop the sessions. The histogram and the ring_buffer are lost at the stop;
--    the file stays.
ALTER EVENT SESSION ExerciseLong ON SERVER STATE = STOP;
ALTER EVENT SESSION ExerciseByHash ON SERVER STATE = STOP;
DROP EVENT SESSION ExerciseLong ON SERVER;
DROP EVENT SESSION ExerciseByHash ON SERVER;
GO
