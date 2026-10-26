-- Module D7 exercise: solution. Runs on the lab, in one session, after 1-start.sql and the
-- two windows. It reads what the routine of the module did not show, then fixes the three
-- problems and measures, and drops what 1-start.sql created.
-- What the night of 1-start.sql did:
--   - the maintenance dropped nix_temp_01, the index of Enrollment.Enrollment on SessionId,
--     "unused" in sys.dm_db_index_usage_stats after a restart (module D6);
--   - the yearly purge deleted the 1,306,336 deliveries of 2024 in a single DELETE: one
--     transaction, whose log could not be truncated before it ended (SIMPLE recovery);
--   - the two windows updated the same campaign and the same delivery in opposite orders.
USE PachadataTraining;
SET NOCOUNT ON;
SET ARITHABORT ON;  -- as in SSMS and in 1-start.sql: the same plans in cache
GO
-- Part 1. The statements that wrote the most log since the evening, from Query Store
-- (avg_log_bytes_used, in bytes per execution).
DECLARE @since datetime2 = (
    SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, SYSDATETIME(), SYSUTCDATETIME()), MAX(restore_date))
    FROM msdb.dbo.restorehistory WHERE destination_database_name = DB_NAME());
SELECT TOP (3) q.query_id,
       CAST(SUM(rs.avg_log_bytes_used * rs.count_executions) / 1048576 AS int) AS log_mb,
       CAST(MAX(rs.max_duration) / 1000 AS int) AS max_duration_ms,
       LEFT(REPLACE(qt.query_sql_text, CHAR(10), ' '), 70) AS query_text
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
WHERE i.end_time > @since
GROUP BY q.query_id, qt.query_sql_text
ORDER BY log_mb DESC;
GO
-- Part 2. What happened to Enrollment.Enrollment during the night (default trace: 46 created,
-- 47 deleted, 164 altered).
DECLARE @trace nvarchar(260) = (
    SELECT CASE WHEN path LIKE N'%log[_]%.trc'
                THEN LEFT(path, LEN(path) - CHARINDEX(N'_', REVERSE(path))) + N'.trc'
                ELSE path END
    FROM sys.traces WHERE is_default = 1);
DECLARE @since datetime = (SELECT MAX(restore_date) FROM msdb.dbo.restorehistory
                           WHERE destination_database_name = DB_NAME());
SELECT t.StartTime, te.name AS event_name, t.ObjectName, t.HostName
FROM sys.fn_trace_gettable(@trace, DEFAULT) AS t
JOIN sys.trace_events AS te ON te.trace_event_id = t.EventClass
WHERE t.EventClass IN (46, 47, 164)
  AND t.DatabaseName = DB_NAME()
  AND t.ObjectID = OBJECT_ID(N'Enrollment.Enrollment')
  AND t.StartTime >= @since
ORDER BY t.StartTime;
GO
-- Part 3. The deadlock of the two windows, from system_health: who was the victim, what each
-- process waited for, and the line of its batch (the windows are batches sent by SSMS).
SELECT COUNT(*) AS targets_flushed FROM sys.dm_xe_session_targets;
DECLARE @graph xml = (
    SELECT TOP (1) CAST(event_data AS xml).query('event/data/value/deadlock')
    FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
    WHERE object_name = N'xml_deadlock_report'
      AND timestamp_utc > DATEADD(MINUTE, -30, SYSUTCDATETIME())
    ORDER BY timestamp_utc DESC);
SELECT p.n.value('@spid', 'int') AS spid,
       CASE WHEN p.n.value('@id', 'varchar(50)')
                 = @graph.value('(deadlock/victim-list/victimProcess/@id)[1]', 'varchar(50)')
            THEN 'victim' ELSE '' END AS role,
       p.n.value('@lockMode', 'varchar(10)') AS lock_wanted,
       p.n.value('@waitresource', 'varchar(60)') AS wait_resource,
       p.n.value('(executionStack/frame/@line)[1]', 'int') AS line_in_batch
FROM @graph.nodes('deadlock/process-list/process') AS p(n)
ORDER BY role DESC;
GO
-- Part 4. The recommendation of the engine is to force the plan of the evening. It used
-- nix_temp_01, which no longer exists: the forcing fails, and Query Store says why.
DECLARE @query_id bigint, @plan_id bigint;
SELECT TOP (1) @query_id = p.query_id, @plan_id = p.plan_id
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Enrollment.GetAttendanceSheet')
ORDER BY p.plan_id;
EXEC sys.sp_query_store_force_plan @query_id = @query_id, @plan_id = @plan_id;
-- The plan in cache would be reused as it is: the forcing applies at the next compilation.
EXEC sys.sp_recompile N'Enrollment.GetAttendanceSheet';
CREATE TABLE #Sink (LastName varchar(50), FirstName varchar(50), Company varchar(100),
                    WaitingList bit);
INSERT #Sink EXEC Enrollment.GetAttendanceSheet @SessionId = 9000;
DROP TABLE #Sink;
WAITFOR DELAY '00:00:02';  -- a failure can take a second or two to show (module 4)
SELECT plan_id, is_forced_plan, force_failure_count, last_force_failure_reason_desc
FROM sys.query_store_plan
WHERE query_id = @query_id;
EXEC sys.sp_query_store_unforce_plan @query_id = @query_id, @plan_id = @plan_id;
GO
-- Part 5. The fixes.
-- 5a. The index, recreated. The plan of the procedure is recompiled: the index is new.
CREATE INDEX nix_temp_01 ON Enrollment.Enrollment (SessionId);
GO
SET STATISTICS IO ON;
EXEC Enrollment.GetAttendanceSheet @SessionId = 9000;
SET STATISTICS IO OFF;
GO
-- 5b. The log: the DELETE has ended, but log_reuse_wait_desc keeps the reason of the last
-- attempt to truncate until the next one. An automatic checkpoint may already have run (the
-- column then says NOTHING); otherwise the CHECKPOINT below truncates the log.
SELECT log_reuse_wait_desc FROM sys.databases WHERE database_id = DB_ID();
CHECKPOINT;
SELECT d.log_reuse_wait_desc,
       CAST(l.total_log_size_in_bytes / 1048576.0 AS decimal(10, 1)) AS log_mb,
       CAST(l.used_log_space_in_percent AS decimal(5, 1)) AS used_pct
FROM sys.databases AS d
CROSS JOIN sys.dm_db_log_space_usage AS l
WHERE d.database_id = DB_ID();
GO
-- 5c. The purge, as it should run: by batches, one transaction per batch, with the procedure
-- of the base. Measured here on the deliveries of 2023, a checkpoint between batches being
-- what SIMPLE recovery does on its own: the log does not grow.
DECLARE @c int;
DECLARE campaigns CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT CampaignId FROM Marketing.Delivery
    WHERE SendDate >= '20230101' AND SendDate < '20240101';
CREATE TABLE #Purge (CampaignId int, Deleted bigint, Batches int, BatchSize int);
OPEN campaigns; FETCH NEXT FROM campaigns INTO @c;
WHILE @@FETCH_STATUS = 0
BEGIN
    INSERT #Purge EXEC Marketing.PurgeDeliveries @CampaignId = @c, @BatchSize = 20000;
    FETCH NEXT FROM campaigns INTO @c;
END;
CLOSE campaigns; DEALLOCATE campaigns;
SELECT COUNT(*) AS campaigns, SUM(Deleted) AS deliveries_deleted FROM #Purge;
DROP TABLE #Purge;
SELECT CAST(l.total_log_size_in_bytes / 1048576.0 AS decimal(10, 1)) AS log_mb,
       CAST(l.used_log_space_in_percent AS decimal(5, 1)) AS used_pct
FROM sys.dm_db_log_space_usage AS l;
GO
-- 5d. The deadlock: both windows must take the campaign first, then the delivery (or the
-- tracking must not update the campaign at all). Nothing to run here: the order is in the
-- code of the two programs.
-- Cleanup: the procedure of the exercise. The next 00-setup.sql restores the base.
DROP PROCEDURE IF EXISTS Enrollment.GetAttendanceSheet;
GO
