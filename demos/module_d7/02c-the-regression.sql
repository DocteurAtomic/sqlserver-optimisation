-- Clip D7.2, the regression of the back office. Runs on the lab, in one session, after
-- charge.sh has played the night. Reads only.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- Step 1. The search of the back office, interval by interval: which plan ran, how many
-- times, how many reads per call (module 4, clip 2). Times in UTC.
SELECT CONVERT(char(5), CAST(i.start_time AS time), 108) AS interval_utc,
       rs.plan_id, rs.count_executions,
       CAST(rs.avg_logical_io_reads AS int) AS avg_reads,
       CAST(rs.avg_cpu_time AS int) AS avg_cpu_us
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
ORDER BY i.start_time, rs.plan_id;
GO
-- Step 2. Each plan: its shape, when it was compiled, and the value of the parameter it was
-- compiled for, written in the plan (Query Store does not keep the parameters of the calls).
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT p.plan_id, p.last_compile_start_time,
       x.value('(//ParameterList/ColumnReference[@Column="@LastName"]/@ParameterCompiledValue)[1]',
               'nvarchar(60)') AS compiled_for,
       CASE WHEN x.exist('//IndexScan[@Lookup="1"]') = 1 THEN 'seek + key lookup'
            ELSE 'clustered index scan' END AS plan_shape
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
CROSS APPLY (SELECT CAST(p.query_plan AS xml) AS x) AS c
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
ORDER BY p.plan_id;
GO
-- Step 3. What happened to Contact.Contact during the night: the default trace records the
-- changes of objects (event 164, Object:Altered) with the host name of the session.
DECLARE @trace nvarchar(260) = (
    SELECT CASE WHEN path LIKE N'%log[_]%.trc'
                THEN LEFT(path, LEN(path) - CHARINDEX(N'_', REVERSE(path))) + N'.trc'
                ELSE path END
    FROM sys.traces WHERE is_default = 1);
DECLARE @since datetime = (SELECT MAX(restore_date) FROM msdb.dbo.restorehistory
                           WHERE destination_database_name = DB_NAME());
SELECT t.StartTime, te.name AS event_name, t.ObjectName, t.HostName, t.LoginName
FROM sys.fn_trace_gettable(@trace, DEFAULT) AS t
JOIN sys.trace_events AS te ON te.trace_event_id = t.EventClass
WHERE t.EventClass = 164
  AND t.DatabaseName = DB_NAME()
  AND t.ObjectID = OBJECT_ID(N'Contact.Contact')
  AND t.StartTime >= @since
ORDER BY t.StartTime;
GO
