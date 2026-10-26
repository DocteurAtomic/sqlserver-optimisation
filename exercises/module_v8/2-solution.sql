-- Exercise of module V8, solution. Runs on the lab, in one session, after 1-start.sql.
-- Part 1: the memory grant feedback of Elearning.LongestActivities at levels 140 and 170,
-- its persistence, then turned off for this query only by a Query Store hint. Part 2: the
-- optional parameter plan optimization on Contact.FindProspects. Drops at the end what
-- 1-start.sql created and sets the database back to level 170.
-- Turn on the actual plan in SSMS (Ctrl+M): MemoryGrantInfo is in the properties of the
-- SELECT operator.
USE PachadataTraining;
GO
-- The memory granted to the sort at its last run and the memory it used, in KB, and the
-- pages it spilled to tempdb.
CREATE OR ALTER VIEW Tools.LongestActivitiesGrant
AS
SELECT qs.execution_count, qs.last_grant_kb, qs.last_used_grant_kb, qs.last_spills
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE st.objectid = OBJECT_ID(N'Elearning.LongestActivities') AND st.dbid = DB_ID()
  AND qs.last_grant_kb > 0;
GO
-- Part 1, question 1. At level 140, the row mode memory grant feedback (level 150) does not
-- exist: three runs, the same grant, a spill each time. The Query Store is cleared first,
-- so that a previous attempt does not bring back its feedback.
ALTER DATABASE CURRENT SET QUERY_STORE CLEAR;
ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 140;
GO
EXEC Elearning.LongestActivities @Since = '20110101', @MinSeconds = 0;
SELECT * FROM Tools.LongestActivitiesGrant;
GO 3
-- Question 2. At level 170: the first run spills, the second receives a larger grant
-- (IsMemoryGrantFeedbackAdjusted = Yes: Adjusting) and does not spill.
ALTER DATABASE CURRENT SET COMPATIBILITY_LEVEL = 170;
GO
EXEC Elearning.LongestActivities @Since = '20110101', @MinSeconds = 0;
SELECT * FROM Tools.LongestActivitiesGrant;
GO 3
-- Question 3. The feedback in the Query Store. Filter on feature_id: feature_desc contains
-- spaces ('Memory Grant Feedback'), and a filter on 'MemoryGrantFeedback' returns nothing.
SELECT q.query_id, f.plan_id, f.feature_id, f.feature_desc, f.state_desc, f.feedback_data
FROM sys.query_store_plan_feedback AS f
JOIN sys.query_store_plan AS p ON p.plan_id = f.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Elearning.LongestActivities');
GO
-- Question 4. The plan is thrown away: the first run of the new plan receives the
-- corrected grant at once, brought back from the Query Store.
EXEC sys.sp_recompile N'Elearning.LongestActivities';
GO
EXEC Elearning.LongestActivities @Since = '20110101', @MinSeconds = 0;
SELECT * FROM Tools.LongestActivitiesGrant;
GO
-- Question 5. The feedback turned off for this query only, without touching the code: a
-- Query Store hint. The database keeps its configuration for every other query.
DECLARE @query_id bigint =
    (SELECT TOP (1) q.query_id FROM sys.query_store_query AS q
     WHERE q.object_id = OBJECT_ID(N'Elearning.LongestActivities'));
EXEC sys.sp_query_store_set_hints @query_id = @query_id,
     @query_hints = N'OPTION (USE HINT (''DISABLE_ROW_MODE_MEMORY_GRANT_FEEDBACK''), MAXDOP 1)';
SELECT query_id, query_hint_text FROM sys.query_store_query_hints;
EXEC sys.sp_recompile N'Elearning.LongestActivities';
GO
EXEC Elearning.LongestActivities @Since = '20110101', @MinSeconds = 0;
SELECT * FROM Tools.LongestActivitiesGrant;
GO 2
DECLARE @query_id bigint = (SELECT TOP (1) query_id FROM sys.query_store_query_hints);
EXEC sys.sp_query_store_clear_hints @query_id = @query_id;
GO
-- Part 2, question 1. A search by name, then a search by zip code, on the same procedure.
SET STATISTICS IO ON;
EXEC Contact.FindProspects @LastName = 'Kowalski';
EXEC Contact.FindProspects @ZipCode = '62086';
SET STATISTICS IO OFF;
GO
-- Question 2. The variants: which optional parameter did OPPO keep?
EXEC sys.sp_query_store_flush_db;
SELECT v.parent_query_id, v.query_variant_query_id,
       SUBSTRING(qt.query_sql_text, CHARINDEX(N'option (PLAN PER VALUE', qt.query_sql_text), 200) AS VariantHint
FROM sys.query_store_query_variant AS v
JOIN sys.query_store_query AS q ON q.query_id = v.query_variant_query_id
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
WHERE qt.query_sql_text LIKE N'%ProspectUS%';
GO
-- Question 3. The same two searches with OPPO turned off for this procedure by a hint
-- written in the code, then the same order.
CREATE OR ALTER PROCEDURE Contact.FindProspects
    @ZipCode varchar(10) = NULL,
    @LastName varchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT FirstName, LastName, ZipCode, City
    FROM Contact.ProspectUS
    WHERE (ZipCode = @ZipCode OR @ZipCode IS NULL)
      AND (LastName = @LastName OR @LastName IS NULL)
    OPTION (USE HINT ('DISABLE_OPTIONAL_PARAMETER_OPTIMIZATION'));
END;
GO
SET STATISTICS IO ON;
EXEC Contact.FindProspects @LastName = 'Kowalski';
EXEC Contact.FindProspects @ZipCode = '62086';
SET STATISTICS IO OFF;
GO
-- Clean-up: what 1-start.sql created.
DROP VIEW Tools.LongestActivitiesGrant;
DROP PROCEDURE Elearning.LongestActivities, Contact.FindProspects;
DROP INDEX nix_prospectus_lastname ON Contact.ProspectUS;
GO
