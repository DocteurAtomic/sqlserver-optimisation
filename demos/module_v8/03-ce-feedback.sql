-- Clip V8.3: the cardinality estimation feedback. The problem of module V3 replayed (the
-- statistics of Contact.Contact dropped, AUTO_CREATE_STATISTICS off); the targeting report
-- compiled ten times with the CE feedback for expressions of SQL Server 2025, then run
-- twenty times on one plan with the CE feedback of SQL Server 2022 alone. Runs on the lab,
-- in one session, after 00-setup.sql. Changes the database (statistics,
-- AUTO_CREATE_STATISTICS, one database scoped configuration, set back at the end); the
-- 00-setup.sql of the next module restores it. Lasts about a minute.
-- In SSMS, tick Query > Query Options > Results > Discard results after execution: the
-- report returns 29,386 rows at each of its 31 runs.
-- What the feedback for expressions learns is kept by the instance, by database_id, and
-- survives a restore of the database (measured in modules V3 and V8): on a lab where this
-- script has already run, step 2 shows the corrected estimate from the first compilation.
-- Measured on a database that had never seen it: the correction came at the 4th, 5th and
-- 8th compilation (three trials).
USE PachadataTraining;
GO
SET NOCOUNT ON;
SET ARITHABORT ON;
GO
-- 1. The problem of module V3: AUTO_CREATE_STATISTICS off, the statistics the optimizer
--    had created on Contact.Contact dropped. Gender and BirthDate have no statistic left.
ALTER DATABASE CURRENT SET AUTO_CREATE_STATISTICS OFF;
GO
DECLARE @sql nvarchar(max) = N'';
SELECT @sql += N'DROP STATISTICS Contact.Contact.' + QUOTENAME(name) + N';'
FROM sys.stats
WHERE object_id = OBJECT_ID(N'Contact.Contact') AND auto_created = 1;
EXEC sys.sp_executesql @sql;
GO
-- 2. The feedback for expressions (on by default) learns from one compilation to the
--    next, not from the runs of a cached plan: the report is recompiled before each of ten
--    runs. After each one: the contacts the plan expects from the scan of Contact, the
--    pages read, and whether the plan has a CardinalityFeedback element.
CREATE TABLE #Compilations (Compilation int IDENTITY, EstimatedContacts float, Reads bigint, CardinalityFeedback bit);
GO
EXEC sys.sp_recompile N'Marketing.GetCampaignTargets';
EXEC Marketing.GetCampaignTargets @Gender = 'F', @BornFrom = '19700101', @BornBefore = '19930101';
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
INSERT #Compilations (EstimatedContacts, Reads, CardinalityFeedback)
SELECT qp.query_plan.value('(//RelOp[IndexScan/Object/@Table="[Contact]"]/@EstimateRows)[1]', 'float'),
       qs.last_logical_reads,
       qp.query_plan.exist('//CardinalityFeedback')
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE st.objectid = OBJECT_ID(N'Marketing.GetCampaignTargets') AND st.dbid = DB_ID();
GO 10
SELECT * FROM #Compilations ORDER BY Compilation;
GO
-- 3. What the instance remembers for this database: one row per expression observed,
--    the five most observed first.
SELECT COUNT(*) AS Fingerprints FROM sys.dm_exec_ce_feedback_cache WHERE database_id = DB_ID();
SELECT TOP (5) fingerprint, feedback, observed_count, state
FROM sys.dm_exec_ce_feedback_cache
WHERE database_id = DB_ID()
ORDER BY observed_count DESC;
GO
-- 4. The CE feedback of the query alone, as in SQL Server 2022: the feedback for
--    expressions turned off, and twenty runs on the same plan. After each one: the pages
--    read, the generation of the plan, and the state of the feedback (feature_id = 1).
ALTER DATABASE SCOPED CONFIGURATION SET CE_FEEDBACK_FOR_EXPRESSIONS = OFF;
EXEC sys.sp_recompile N'Marketing.GetCampaignTargets';
CREATE TABLE #Runs (Run int IDENTITY, Reads bigint, PlanGeneration bigint, Feedback nvarchar(60), FeedbackData nvarchar(200));
GO
EXEC Marketing.GetCampaignTargets @Gender = 'F', @BornFrom = '19700101', @BornBefore = '19930101';
INSERT #Runs (Reads, PlanGeneration, Feedback, FeedbackData)
SELECT qs.last_logical_reads, qs.plan_generation_num,
       (SELECT TOP (1) f.state_desc FROM sys.query_store_plan_feedback AS f WHERE f.feature_id = 1),
       (SELECT TOP (1) f.feedback_data FROM sys.query_store_plan_feedback AS f WHERE f.feature_id = 1)
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE st.objectid = OBJECT_ID(N'Marketing.GetCampaignTargets') AND st.dbid = DB_ID();
GO 20
SELECT * FROM #Runs ORDER BY Run;
DROP TABLE #Runs;
GO
-- 5. The verdict the Query Store kept, the hints it set (none), the plans of the report.
SELECT f.plan_id, f.feature_desc, f.state_desc, f.feedback_data, f.create_time, f.last_updated_time
FROM sys.query_store_plan_feedback AS f
WHERE f.feature_id = 1;
SELECT query_id, query_hint_text, source_desc
FROM sys.query_store_query_hints;
SELECT COUNT(*) AS PlansOfTheReport
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Marketing.GetCampaignTargets');
GO
-- 6. The feedback for expressions turned back on: what it learned in step 2 applies again
--    at the next compilation.
ALTER DATABASE SCOPED CONFIGURATION SET CE_FEEDBACK_FOR_EXPRESSIONS = ON;
EXEC sys.sp_recompile N'Marketing.GetCampaignTargets';
GO
EXEC Marketing.GetCampaignTargets @Gender = 'F', @BornFrom = '19700101', @BornBefore = '19930101';
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
INSERT #Compilations (EstimatedContacts, Reads, CardinalityFeedback)
SELECT qp.query_plan.value('(//RelOp[IndexScan/Object/@Table="[Contact]"]/@EstimateRows)[1]', 'float'),
       qs.last_logical_reads,
       qp.query_plan.exist('//CardinalityFeedback')
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE st.objectid = OBJECT_ID(N'Marketing.GetCampaignTargets') AND st.dbid = DB_ID();
SELECT TOP (1) * FROM #Compilations ORDER BY Compilation DESC;
DROP TABLE #Compilations;
GO
