-- Clip V8.2: the DOP feedback of SQL Server 2022, on by default in SQL Server 2025. A
-- parallel aggregate over the 7.8 million rows of Elearning.Activity, run ten times at a
-- MAXDOP of 8 for the database, then what sys.query_store_plan_feedback says of it. Runs on
-- the lab, in one session, after 00-setup.sql. Creates Elearning.GetActivityAudience and
-- drops it; sets the MAXDOP of the database to 8, then back to 2. Lasts about a minute.
-- Measured on the lab (a container limited to 4 processors, in which the engine sees 22):
-- the feedback never started, after 10 runs as after 20 (see SORTIES.md).
USE PachadataTraining;
GO
SET NOCOUNT ON;
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 8;
GO
-- The audience of the e-learning activity, per type of event and device: four distinct
-- counts.
CREATE OR ALTER PROCEDURE Elearning.GetActivityAudience
AS
SELECT a.EventTypeCode, a.Device,
       COUNT(DISTINCT a.ContactId)    AS Learners,
       COUNT(DISTINCT a.EnrollmentId) AS Enrollments,
       COUNT(DISTINCT a.EventTime)    AS Moments,
       COUNT(DISTINCT CONCAT(a.ContactId, '-', a.Step)) AS Steps
FROM Elearning.Activity AS a
GROUP BY a.EventTypeCode, a.Device;
GO
-- 1. Ten runs. After each one, the degree of parallelism of the last run, its CPU and
--    elapsed times in ms, and the state of the DOP feedback (feature_id = 3), if any.
CREATE TABLE #Runs (Run int IDENTITY, LastDop bigint, CpuMs bigint, ElapsedMs bigint, Feedback nvarchar(60));
GO
EXEC Elearning.GetActivityAudience;
INSERT #Runs (LastDop, CpuMs, ElapsedMs, Feedback)
SELECT qs.last_dop, qs.last_worker_time / 1000, qs.last_elapsed_time / 1000,
       (SELECT TOP (1) f.state_desc FROM sys.query_store_plan_feedback AS f WHERE f.feature_id = 3)
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE st.objectid = OBJECT_ID(N'Elearning.GetActivityAudience') AND st.dbid = DB_ID();
GO 10
SELECT * FROM #Runs ORDER BY Run;
DROP TABLE #Runs;
GO
-- 2. What the Query Store kept for this procedure, all features together.
SELECT f.feature_desc, f.state_desc, f.feedback_data
FROM sys.query_store_plan_feedback AS f
JOIN sys.query_store_plan AS p ON p.plan_id = f.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Elearning.GetActivityAudience');
GO
-- 3. The waits of this session: the engine waits on its hash tables and its exchanges, not
--    on the processors the container takes away from it.
SELECT TOP (5) wait_type, waiting_tasks_count, wait_time_ms
FROM sys.dm_exec_session_wait_stats
WHERE session_id = @@SPID
ORDER BY wait_time_ms DESC;
GO
DROP PROCEDURE Elearning.GetActivityAudience;
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 2;
GO
