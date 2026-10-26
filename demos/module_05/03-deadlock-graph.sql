-- ci: skip (reads the deadlocks of the load: run after charge.sh has run for a minute)
-- Clip 5.3: the deadlocks of the database in the files of system_health, the session that
-- runs on every instance; the processes and the resources of the last one. Runs on the
-- lab, in one session. Nothing is created: system_health is only read.
USE master;
GO
SET NOCOUNT ON;
GO
-- 1. system_health: running since the instance started, two targets, and a dispatch
--    latency of 120 seconds: a deadlock can take two minutes to reach the file. Reading
--    sys.dm_xe_session_targets, as this query does, flushes the buffers of every session
--    to its targets: the file is up to date for the next query.
SELECT s.name, t.target_name, ss.max_dispatch_latency / 1000 AS dispatch_latency_s
FROM sys.dm_xe_sessions AS s
JOIN sys.dm_xe_session_targets AS t ON t.event_session_address = s.address
JOIN sys.server_event_sessions AS ss ON ss.name = s.name
WHERE s.name = N'system_health';
GO
-- 2. The deadlocks that involve the database since 00-setup.sql created Course.ChangeRoom
--    (create_date is local time, the file gives UTC). The file target is read rather than
--    the ring_buffer: on a busy instance the ring_buffer forgets, and its XML is capped at
--    4 MB.
DECLARE @since_utc datetime2 = (
    SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, SYSDATETIME(), SYSUTCDATETIME()), create_date)
    FROM PachadataTraining.sys.objects
    WHERE object_id = OBJECT_ID(N'PachadataTraining.Course.ChangeRoom'));
WITH reports AS (
    SELECT timestamp_utc, CAST(event_data AS xml) AS x
    FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
    WHERE object_name = N'xml_deadlock_report'
      AND timestamp_utc > @since_utc
)
SELECT COUNT(*) AS deadlocks, MIN(timestamp_utc) AS first_utc, MAX(timestamp_utc) AS last_utc
FROM reports
WHERE x.exist('//process[@currentdbname = "PachadataTraining"]') = 1;

-- 3. The last one: copied once into a variable, then read process by process.
DECLARE @graph xml = (
    SELECT TOP (1) CAST(event_data AS xml).query('event/data/value/deadlock')
    FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
    WHERE object_name = N'xml_deadlock_report'
      AND timestamp_utc > @since_utc
      AND CAST(event_data AS xml).exist('//process[@currentdbname = "PachadataTraining"]') = 1
    ORDER BY timestamp_utc DESC);

-- The processes: who, what it ran, what it waited for.
SELECT p.n.value('@spid', 'int') AS spid,
       p.n.value('@hostname', 'nvarchar(128)') AS host,
       CASE WHEN p.n.value('@id', 'varchar(50)')
                 = @graph.value('(deadlock/victim-list/victimProcess/@id)[1]', 'varchar(50)')
            THEN 'victim' ELSE '' END AS role,
       p.n.value('(executionStack/frame/@procname)[1]', 'nvarchar(200)') AS procname,
       p.n.value('(executionStack/frame/@line)[1]', 'int') AS line,
       p.n.value('@lockMode', 'varchar(10)') AS lock_wanted,
       p.n.value('@waitresource', 'varchar(60)') AS wait_resource,
       p.n.value('@waittime', 'int') AS wait_ms,
       p.n.value('@logused', 'int') AS log_used
FROM @graph.nodes('deadlock/process-list/process') AS p(n)
ORDER BY role DESC;

-- The statement each one was running when the deadlock was found.
SELECT p.n.value('@hostname', 'nvarchar(128)') AS host,
       LEFT(LTRIM(REPLACE(REPLACE(p.n.value('(executionStack/frame)[1]', 'nvarchar(max)'),
                                  CHAR(13), N' '), CHAR(10), N' ')), 60) AS statement
FROM @graph.nodes('deadlock/process-list/process') AS p(n);

-- The resources: one lock per row, who holds it and who wants it.
SELECT r.n.value('@objectname', 'nvarchar(200)') AS object_name,
       r.n.value('@indexname', 'nvarchar(200)') AS index_name,
       r.n.value('(owner-list/owner/@mode)[1]', 'varchar(10)') AS held_mode,
       ho.n.value('@hostname', 'nvarchar(128)') AS held_by,
       r.n.value('(waiter-list/waiter/@mode)[1]', 'varchar(10)') AS wanted_mode,
       wo.n.value('@hostname', 'nvarchar(128)') AS wanted_by
FROM @graph.nodes('deadlock/resource-list/*') AS r(n)
OUTER APPLY @graph.nodes('deadlock/process-list/process') AS ho(n)
OUTER APPLY @graph.nodes('deadlock/process-list/process') AS wo(n)
WHERE ho.n.value('@id', 'varchar(50)') = r.n.value('(owner-list/owner/@id)[1]', 'varchar(50)')
  AND wo.n.value('@id', 'varchar(50)') = r.n.value('(waiter-list/waiter/@id)[1]', 'varchar(50)');

-- 4. The graph itself. In SSMS, click it, save the XML as a file with the .xdl extension,
--    and open that file: SSMS draws the graph.
SELECT @graph AS deadlock_graph;
GO
