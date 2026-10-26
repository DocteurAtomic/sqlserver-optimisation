-- Clip V5.1: the plan cache. The complaint of the quality team, the call that is fast in
-- SSMS and slow in the sender of the surveys, the two plans of the procedure and the
-- session option that separates them, then what makes the engine compile. Runs on the lab,
-- in one session, after 00-setup.sql. sp_recompile at the end empties the cache of the
-- procedure: clip V5.2 plays the morning of the tool again.
USE PachadataTraining;
GO
-- SSMS sets ARITHABORT ON for its sessions; written here so that sqlcmd does the same.
SET ARITHABORT ON;
SET NOCOUNT ON;
GO
-- 1. The developer checks the call in SSMS: the recipients of one evaluation.
SET STATISTICS IO, TIME ON;
EXEC Report.RecipientsByCampaign @CampaignId = 17389;
SET STATISTICS IO, TIME OFF;
GO
-- 2. What the cache knows of the procedure: one row per cached plan.
SELECT plan_handle, cached_time, execution_count,
       min_logical_reads, max_logical_reads,
       total_worker_time / execution_count / 1000 AS AvgCpuMs
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Report.RecipientsByCampaign');
GO
-- 3. The plans themselves, and the attribute that keeps them apart: set_options, the session
--    options of the compilation. 4096 is ARITHABORT.
SELECT cp.plan_handle, cp.objtype, cp.usecounts, cp.size_in_bytes,
       CAST(pa.value AS int) AS set_options,
       CASE WHEN CAST(pa.value AS int) & 4096 = 4096 THEN 'ON' ELSE 'OFF' END AS ArithAbort
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
CROSS APPLY sys.dm_exec_plan_attributes(cp.plan_handle) AS pa
WHERE st.dbid = DB_ID()
  AND st.objectid = OBJECT_ID(N'Report.RecipientsByCampaign')
  AND pa.attribute = N'set_options';
GO
-- 4. The same call with the options of the application.
SET ARITHABORT OFF;
SET STATISTICS IO, TIME ON;
EXEC Report.RecipientsByCampaign @CampaignId = 17389;
SET STATISTICS IO, TIME OFF;
SET ARITHABORT ON;
GO
-- 5. What makes the engine compile: the first call after the plan has left the cache.
--    sp_recompile throws away every plan of the procedure.
EXEC sys.sp_recompile N'Report.RecipientsByCampaign';
GO
SELECT COUNT(*) AS CachedPlans
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Report.RecipientsByCampaign');
GO
SET STATISTICS TIME ON;
EXEC Report.RecipientsByCampaign @CampaignId = 17389;
SET STATISTICS TIME OFF;
GO
SELECT COUNT(*) AS CachedPlans
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Report.RecipientsByCampaign');
GO
