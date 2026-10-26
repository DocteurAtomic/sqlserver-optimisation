-- Exercise of module V5, solution. Runs on the lab, in one session, after 1-start.sql. It
-- lasts about ten seconds. Part 2 creates an extended events session, psp_skipped, and drops
-- it; the end drops the index and the procedure that 1-start.sql created.
USE PachadataTraining;
GO
SET NOCOUNT ON;
GO
-- Part 1. Each order, measured. The quiet module (992, 170 events) is served by a seek in
-- nix_activity_moduleid and one RID lookup per event (the table is a heap); the busy one
-- (808, 49,887 events) by a parallel scan of the heap.
EXEC sys.sp_recompile N'Elearning.GetModuleActivity';
GO
SET STATISTICS IO, TIME ON;
EXEC Elearning.GetModuleActivity @ModuleId = 992;
EXEC Elearning.GetModuleActivity @ModuleId = 808;
SET STATISTICS IO, TIME OFF;
GO
EXEC sys.sp_recompile N'Elearning.GetModuleActivity';
GO
SET STATISTICS IO, TIME ON;
EXEC Elearning.GetModuleActivity @ModuleId = 808;
EXEC Elearning.GetModuleActivity @ModuleId = 992;
SET STATISTICS IO, TIME OFF;
GO
-- The cached plan was compiled for 808: the value is in the plan.
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT pr.n.value('@Column', 'sysname') AS ParameterName,
       pr.n.value('@ParameterCompiledValue', 'nvarchar(50)') AS CompiledValue
FROM sys.dm_exec_procedure_stats AS ps
CROSS APPLY sys.dm_exec_query_plan(ps.plan_handle) AS qp
CROSS APPLY qp.query_plan.nodes('//ParameterList/ColumnReference') AS pr(n)
WHERE ps.database_id = DB_ID() AND ps.object_id = OBJECT_ID(N'Elearning.GetModuleActivity');
GO
-- Part 2. The optimization is on, and the cache holds one plan, of type Proc: no
-- prepared variant, no dispatcher.
SELECT name, value FROM sys.database_scoped_configurations
WHERE name = N'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION';
SELECT cp.objtype, cp.usecounts, LEFT(st.text, 60) AS StartOfText
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
WHERE st.dbid = DB_ID() AND st.text LIKE N'%FROM Elearning.Activity AS a%'
  AND st.text NOT LIKE N'%dm_exec_cached_plans%';
GO
-- Why: the event parameter_sensitive_plan_optimization_skipped_reason, fired at compilation.
-- Report.RecipientsByCampaign is compiled in the same session, for comparison.
CREATE EVENT SESSION psp_skipped ON SERVER
ADD EVENT sqlserver.parameter_sensitive_plan_optimization_skipped_reason
    (ACTION (sqlserver.sql_text) WHERE sqlserver.database_name = N'PachadataTraining'),
ADD EVENT sqlserver.query_with_parameter_sensitivity
    (ACTION (sqlserver.sql_text) WHERE sqlserver.database_name = N'PachadataTraining')
ADD TARGET package0.ring_buffer;
GO
ALTER EVENT SESSION psp_skipped ON SERVER STATE = START;
GO
EXEC sys.sp_recompile N'Elearning.GetModuleActivity';
EXEC sys.sp_recompile N'Report.RecipientsByCampaign';
GO
EXEC Elearning.GetModuleActivity @ModuleId = 992;
GO
EXEC Report.RecipientsByCampaign @CampaignId = 17389;
GO
WITH Target AS (
    SELECT CAST(t.target_data AS xml) AS Data
    FROM sys.dm_xe_session_targets AS t
    JOIN sys.dm_xe_sessions AS s ON s.address = t.event_session_address
    WHERE s.name = N'psp_skipped'
)
SELECT LEFT(TRANSLATE(e.n.value('(action[@name="sql_text"]/value)[1]', 'nvarchar(200)'),
                 CHAR(13) + CHAR(10), N'  '), 56) AS Batch,
       e.n.value('@name', 'sysname') AS EventName,
       d.n.value('@name', 'sysname') AS Field,
       COALESCE(d.n.value('(text)[1]', 'nvarchar(100)'),
                d.n.value('(value)[1]', 'nvarchar(200)')) AS Value
FROM Target
CROSS APPLY Data.nodes('//event') AS e(n)
CROSS APPLY e.n.nodes('data') AS d(n)
WHERE d.n.value('@name', 'sysname') IN (N'reason', N'psp_optimization_supported',
                                        N'interesting_predicate_details');
-- The TableId of the details is the object_id of Marketing.Delivery.
SELECT OBJECT_ID(N'Marketing.Delivery') AS DeliveryObjectId;
GO
ALTER EVENT SESSION psp_skipped ON SERVER STATE = STOP;
DROP EVENT SESSION psp_skipped ON SERVER;
GO
-- Part 3. Two remedies, measured on the same calls. OPTION (RECOMPILE) gives each call its
-- plan, for a compilation per call. OPTIMIZE FOR the quiet module keeps the seek for all:
-- the busy module reads more pages than with its own plan, but takes less processor time,
-- the parallel scan of 7.8 million rows being the expensive part.
CREATE OR ALTER PROCEDURE Elearning.GetModuleActivity @ModuleId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.EventTypeCode, a.Device, COUNT(*) AS Events, SUM(a.DurationSeconds) AS Seconds
    FROM Elearning.Activity AS a
    WHERE a.ModuleId = @ModuleId
    GROUP BY a.EventTypeCode, a.Device
    OPTION (RECOMPILE);
END;
GO
SET STATISTICS IO, TIME ON;
EXEC Elearning.GetModuleActivity @ModuleId = 808;
EXEC Elearning.GetModuleActivity @ModuleId = 992;
SET STATISTICS IO, TIME OFF;
GO
CREATE OR ALTER PROCEDURE Elearning.GetModuleActivity @ModuleId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.EventTypeCode, a.Device, COUNT(*) AS Events, SUM(a.DurationSeconds) AS Seconds
    FROM Elearning.Activity AS a
    WHERE a.ModuleId = @ModuleId
    GROUP BY a.EventTypeCode, a.Device
    OPTION (OPTIMIZE FOR (@ModuleId = 992));
END;
GO
SET STATISTICS IO, TIME ON;
EXEC Elearning.GetModuleActivity @ModuleId = 808;
EXEC Elearning.GetModuleActivity @ModuleId = 992;
SET STATISTICS IO, TIME OFF;
GO
-- Cleanup: what 1-start.sql created.
DROP PROCEDURE Elearning.GetModuleActivity;
DROP INDEX nix_activity_moduleid ON Elearning.Activity;
GO
