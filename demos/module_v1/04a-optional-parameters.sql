-- Clip V1.4: optional parameters. One cached plan for every combination of criteria, then
-- OPTION (RECOMPILE) and parameterized dynamic SQL, measured. Runs on the lab, in one
-- session, after 00-setup.sql. The plan of Course.SearchSessions in the cache is the one
-- compiled for a search by course and language: by the first search of 00-setup.sql, or by
-- the first call below if 03-data-types.sql emptied the cache in between. Reads only, apart
-- from the plan cache. SET ARITHABORT ON, as in SSMS and in 00-setup.sql.
-- OPTIONAL_PARAMETER_OPTIMIZATION is OFF for the database (00-setup.sql): the behavior is
-- that of SQL Server 2022 and earlier. Module V8 shows what SQL Server 2025 does with it on.
USE PachadataTraining;
SET ARITHABORT ON;
GO
SELECT name, value
FROM sys.database_scoped_configurations
WHERE name = N'OPTIONAL_PARAMETER_OPTIMIZATION';
GO
SET STATISTICS IO, TIME ON;
GO
-- 1. The search by course and language, then the page of the coming sessions, which gives
--    only a start date. Both reuse the plan compiled by the first search of the day.
EXEC Course.SearchSessions @CourseId = 25, @LanguageCode = 'FR';
EXEC Course.SearchSessions @StartDate = '20271201';
GO
-- 2. The plan thrown away, and the date search first this time.
EXEC sys.sp_recompile N'Course.SearchSessions';
GO
EXEC Course.SearchSessions @StartDate = '20271201';
EXEC Course.SearchSessions @CourseId = 25, @LanguageCode = 'FR';
GO
-- 3. OPTION (RECOMPILE): the statement is compiled at each call, with the values.
DECLARE @CourseId int = 25, @LanguageCode char(2) = 'FR', @StartDate date = NULL;
SELECT SessionId, CourseId, LanguageCode, StartDate, TrainingRoomId, Price
FROM Course.Session
WHERE (CourseId = @CourseId OR @CourseId IS NULL)
  AND (LanguageCode = @LanguageCode OR @LanguageCode IS NULL)
  AND (StartDate >= @StartDate OR @StartDate IS NULL)
OPTION (RECOMPILE);
GO
DECLARE @CourseId int = NULL, @LanguageCode char(2) = NULL, @StartDate date = '20271201';
SELECT SessionId, CourseId, LanguageCode, StartDate, TrainingRoomId, Price
FROM Course.Session
WHERE (CourseId = @CourseId OR @CourseId IS NULL)
  AND (LanguageCode = @LanguageCode OR @LanguageCode IS NULL)
  AND (StartDate >= @StartDate OR @StartDate IS NULL)
OPTION (RECOMPILE);
GO
-- 4. Parameterized dynamic SQL: Demo.SearchSessions_Fixed builds only the criteria it
--    receives and passes the values as parameters of sp_executesql.
EXEC Demo.SearchSessions_Fixed @CourseId = 25, @LanguageCode = 'FR';
EXEC Demo.SearchSessions_Fixed @StartDate = '20271201';
GO
SET STATISTICS IO, TIME OFF;
GO
-- The plans that dynamic SQL left in the cache: one per combination of criteria.
SELECT qs.execution_count, qs.last_logical_reads, SUBSTRING(st.text, 1, 200) AS QueryText
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
WHERE st.text LIKE N'(@CourseId int, @LanguageCode char(2), @StartDate date)%'
  AND pa.attribute = N'dbid' AND CONVERT(int, pa.value) = DB_ID();
GO
