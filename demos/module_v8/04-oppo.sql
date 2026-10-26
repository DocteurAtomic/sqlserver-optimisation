-- Clip V8.4: the optional parameter plan optimization (OPPO) of SQL Server 2025 on the
-- search of module V1, then how to turn a feature off at the right scope: one query
-- through a Query Store hint, the whole database through the compatibility level. Runs on
-- the lab, in one session, after 00-setup.sql (whose first search of the day compiled the
-- search for a course and a language). Sets a Query Store hint and clears it; changes the
-- compatibility level and sets it back to 170. Reads only, apart from the plan cache.
USE PachadataTraining;
SET ARITHABORT ON;
GO
SELECT name, value
FROM sys.database_scoped_configurations
WHERE name = N'OPTIONAL_PARAMETER_OPTIMIZATION';
GO
SET STATISTICS IO ON;
GO
-- 1. The search by course and language, then the page of the coming sessions, which gives
--    only a start date, then a search by language only. In module V1, with OPPO off, the
--    date search reused the plan of the first search of the day and read 38,631 pages.
EXEC Course.SearchSessions @CourseId = 25, @LanguageCode = 'FR';
EXEC Course.SearchSessions @StartDate = '20271201';
EXEC Course.SearchSessions @LanguageCode = 'FR';
GO
SET STATISTICS IO OFF;
GO
-- 2. The cache: the procedure, and one prepared plan per query variant.
SELECT cp.objtype, cp.usecounts, LEFT(st.text, 60) AS QueryText
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
WHERE st.dbid = DB_ID()
  AND (st.objectid = OBJECT_ID(N'Course.SearchSessions')
       OR st.text LIKE N'(@CourseId int,@LanguageCode char(2),@StartDate date)%');
GO
-- 3. The Query Store: the parent query, its variants, and the hint OPPO wrote in the text
--    of each variant (PLAN PER VALUE ... optional_predicate).
EXEC sys.sp_query_store_flush_db;
SELECT v.parent_query_id, v.query_variant_query_id, v.dispatcher_plan_id,
       SUBSTRING(qt.query_sql_text, CHARINDEX(N'option (PLAN PER VALUE', qt.query_sql_text), 200) AS VariantHint
FROM sys.query_store_query_variant AS v
JOIN sys.query_store_query AS q ON q.query_id = v.query_variant_query_id
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id;
GO
-- 4. Turning OPPO off for this query only: a Query Store hint on the parent query, without
--    touching the code. The plan of the procedure is thrown away; the course search
--    compiles first, and the date search reuses its plan, as in module V1.
DECLARE @query_id bigint = (SELECT TOP (1) v.parent_query_id FROM sys.query_store_query_variant AS v);
EXEC sys.sp_query_store_set_hints @query_id = @query_id,
     @query_hints = N'OPTION (USE HINT (''DISABLE_OPTIONAL_PARAMETER_OPTIMIZATION''))';
SELECT query_id, query_hint_text, source_desc FROM sys.query_store_query_hints;
EXEC sys.sp_recompile N'Course.SearchSessions';
GO
SET STATISTICS IO ON;
EXEC Course.SearchSessions @CourseId = 25, @LanguageCode = 'FR';
EXEC Course.SearchSessions @StartDate = '20271201';
SET STATISTICS IO OFF;
GO
DECLARE @query_id bigint = (SELECT TOP (1) query_id FROM sys.query_store_query_hints);
EXEC sys.sp_query_store_clear_hints @query_id = @query_id;
EXEC sys.sp_recompile N'Course.SearchSessions';
GO
-- 5. The whole database at level 160: OPPO, which needs level 170, is off with everything
--    else that came with 170. Same two searches, then back to 170.
ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 160;
GO
SET STATISTICS IO ON;
EXEC Course.SearchSessions @CourseId = 25, @LanguageCode = 'FR';
EXEC Course.SearchSessions @StartDate = '20271201';
SET STATISTICS IO OFF;
GO
ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 170;
GO
-- 6. The database scoped configurations of intelligent query processing, read from the
--    instance rather than from a list (B085).
SELECT name, value, is_value_default
FROM sys.database_scoped_configurations
WHERE name LIKE N'%FEEDBACK%'
   OR name LIKE N'%BATCH_MODE%'
   OR name LIKE N'%INLINING%'
   OR name LIKE N'%DEFERRED%'
   OR name LIKE N'%INTERLEAVED%'
   OR name LIKE N'%PARAMETER%'
   OR name LIKE N'%SP_EXECUTESQL%'
ORDER BY name;
GO
