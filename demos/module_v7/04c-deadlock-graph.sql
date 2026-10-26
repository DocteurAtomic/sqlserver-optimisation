-- Module V7, clip 4: the deadlock of 04a in system_health. Runs on the lab, in one
-- session, after 04a-deadlock-by-hand.sql or 04b-retry-by-hand.sql.
-- ci: skip (it needs a deadlock in the base: without one, the queries return no rows)
-- Module 5 reads a deadlock graph in detail; this script keeps the locks of the last one.
-- Nothing is created: system_health is only read.
USE master;
GO
SET NOCOUNT ON;
GO
-- Reading the targets of the sessions flushes their buffers to the files.
SELECT COUNT(*) AS targets
FROM sys.dm_xe_session_targets AS t
JOIN sys.dm_xe_sessions AS s ON s.address = t.event_session_address
WHERE s.name = N'system_health';
GO
DECLARE @graph xml = (
    SELECT TOP (1) CAST(event_data AS xml).query('event/data/value/deadlock')
    FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
    WHERE object_name = N'xml_deadlock_report'
      AND CAST(event_data AS xml).exist('//process[@currentdbname = "PachadataTraining"]') = 1
    ORDER BY timestamp_utc DESC);

-- The processes: the victim, the isolation level, the lock each one wanted.
SELECT p.n.value('@spid', 'int') AS spid,
       CASE WHEN p.n.value('@id', 'varchar(50)')
                 = @graph.value('(deadlock/victim-list/victimProcess/@id)[1]', 'varchar(50)')
            THEN 'victim' ELSE '' END AS role,
       p.n.value('@isolationlevel', 'varchar(40)') AS isolation_level,
       p.n.value('@lockMode', 'varchar(10)') AS lock_wanted,
       p.n.value('@waittime', 'int') AS wait_ms
FROM @graph.nodes('deadlock/process-list/process') AS p(n)
ORDER BY role DESC;

-- The resources: the lock held and the lock wanted on each one.
SELECT r.n.value('local-name(.)', 'varchar(30)') AS resource_type,
       r.n.value('@indexname', 'nvarchar(200)') AS index_name,
       r.n.value('(owner-list/owner/@mode)[1]', 'varchar(10)') AS held_mode,
       r.n.value('(waiter-list/waiter/@mode)[1]', 'varchar(10)') AS wanted_mode
FROM @graph.nodes('deadlock/resource-list/*') AS r(n);
GO
