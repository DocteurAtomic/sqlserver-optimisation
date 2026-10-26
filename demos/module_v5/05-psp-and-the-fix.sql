-- Clip V5.5: the parameter sensitive plan optimization, and the end of the module. The
-- configuration found off, turned back on, the morning of the tool played again and
-- measured, then the dispatcher plan and its variants in the cache and in the Query Store,
-- and the monitoring query that loses them. Runs on the lab, in one session, after
-- 04-dynamic-sql.sql (or right after 00-setup.sql). The loop of step 4 lasts a second.
USE PachadataTraining;
GO
SET NOCOUNT ON;
SET ARITHABORT OFF;
GO
-- 1. The investigation: the level of the database, and the configuration of the optimization.
SELECT name, compatibility_level FROM sys.databases WHERE name = DB_NAME();
SELECT name, value, is_value_default
FROM sys.database_scoped_configurations
WHERE name = N'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION';
GO
-- 2. The fix: the optimization back on, as it is by default at level 160 and above.
--    Changing it throws away the plans of the procedure.
ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = ON;
GO
SELECT COUNT(*) AS CachedPlans
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Report.RecipientsByCampaign');
GO
-- 3. The morning of the tool again: the letter first, then one evaluation.
SET STATISTICS IO, TIME ON;
EXEC Report.RecipientsByCampaign @CampaignId = 36;
EXEC Report.RecipientsByCampaign @CampaignId = 17389;
SET STATISTICS IO, TIME OFF;
GO
-- 4. One hundred evaluations, after the letter.
CREATE TABLE #Recipients (LastName varchar(50), FirstName varchar(50), Email varchar(150),
                          SendDate datetime2, Opened bit);
DECLARE @Start datetime2 = SYSDATETIME(),
        @Cpu int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID),
        @CampaignId int = 17291;
WHILE @CampaignId <= 17390
BEGIN
    INSERT INTO #Recipients EXEC Report.RecipientsByCampaign @CampaignId = @CampaignId;
    SET @CampaignId += 1;
END;
SELECT 'with the optimization' AS Run,
       DATEDIFF(millisecond, @Start, SYSDATETIME()) AS ElapsedMs,
       (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID) - @Cpu AS CpuMs;
DROP TABLE #Recipients;
GO
-- 5. The cache: the plan of the procedure holds the dispatcher; each variant has its own
--    entry, a prepared statement that no longer knows its procedure.
SELECT cp.objtype, ce.type AS CacheStore, st.objectid, cp.usecounts,
       RIGHT(st.text, 130) AS EndOfText
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
JOIN sys.dm_os_memory_cache_entries AS ce ON ce.memory_object_address = cp.memory_object_address
WHERE st.dbid = DB_ID()
  AND st.text LIKE N'%FROM Marketing.Delivery AS e%'
  AND st.text NOT LIKE N'%dm_exec_cached_plans%';
GO
-- The boundaries of the dispatcher, read in the plan of the procedure.
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT d.n.value('@LowBoundary', 'float') AS LowBoundary,
       d.n.value('@HighBoundary', 'float') AS HighBoundary,
       d.n.value('(StatisticsInfo/@Statistics)[1]', 'sysname') AS StatisticsName
FROM sys.dm_exec_procedure_stats AS ps
CROSS APPLY sys.dm_exec_query_plan(ps.plan_handle) AS qp
CROSS APPLY qp.query_plan.nodes('//Dispatcher/ParameterSensitivePredicate') AS d(n)
WHERE ps.database_id = DB_ID() AND ps.object_id = OBJECT_ID(N'Report.RecipientsByCampaign');
GO
-- 6. The usual monitoring query, statement by statement, filtered on the procedure name:
--    the variants are gone. sys.dm_exec_procedure_stats still adds them up.
SELECT OBJECT_NAME(st.objectid, st.dbid) AS ObjectName, qs.execution_count,
       qs.total_logical_reads
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE OBJECT_NAME(st.objectid, st.dbid) = N'RecipientsByCampaign';
SELECT OBJECT_NAME(object_id, database_id) AS ProcedureName, execution_count,
       total_logical_reads
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Report.RecipientsByCampaign');
GO
-- 7. The Query Store keeps the link: the parent query, its dispatcher plan and its variants.
EXEC sys.sp_query_store_flush_db;
SELECT OBJECT_NAME(pq.object_id) AS ParentObject, v.parent_query_id,
       v.query_variant_query_id, v.dispatcher_plan_id, p.plan_id, p.plan_type_desc
FROM sys.query_store_query_variant AS v
JOIN sys.query_store_query AS pq ON pq.query_id = v.parent_query_id
JOIN sys.query_store_plan AS p ON p.query_id = v.query_variant_query_id
WHERE pq.object_id = OBJECT_ID(N'Report.RecipientsByCampaign');
GO
-- 8. The parameterized query of clip V5.4 is dispatched the same way.
DECLARE @sql nvarchar(max) = N'SELECT c.LastName, c.FirstName, c.Email, e.SendDate, e.Opened
FROM Marketing.Delivery AS e
JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
WHERE e.CampaignId = @CampaignId;';
EXEC sys.sp_executesql @sql, N'@CampaignId int', @CampaignId = 36;
SET STATISTICS IO ON;
EXEC sys.sp_executesql @sql, N'@CampaignId int', @CampaignId = 17389;
SET STATISTICS IO OFF;
GO
-- The prepared statement holds the dispatcher; its variants carry ObjectID = 0, those of
-- the procedure carry the object_id of the procedure.
SELECT cp.objtype, cp.usecounts,
       CASE WHEN CHARINDEX(N'PLAN PER VALUE', st.text) = 0 THEN N'(dispatcher)'
            ELSE SUBSTRING(st.text, CHARINDEX(N'PLAN PER VALUE', st.text), 64) END AS Variant
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
WHERE st.dbid = DB_ID()
  AND st.text LIKE N'(@CampaignId int)SELECT c.LastName, c.FirstName%'
ORDER BY Variant;
GO
