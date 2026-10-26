-- Clip 3.4: the warnings of a plan. Runs on the lab, in one session, after 00-setup.sql,
-- before any other run of query 1. Reads only, apart from the procedure cache of this
-- database, emptied at the start so that the queries compile. Turn on the actual plan in
-- SSMS (Ctrl+M).
-- The memory grant feedback, kept in the Query Store, changes the memory given to the
-- following runs of query 1, and not always upwards: the spill may come and go when the
-- script is run again. 00-setup.sql restores the base and starts it over.
USE PachadataTraining;
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
SET STATISTICS IO, TIME ON;
GO
-- 1. The query of clip 3.3 with the campaign in a variable, now sorted by name. The sort
--    receives the memory the optimizer computed for 245 rows, and gets 107,994: the actual
--    plan shows a warning on the Sort operator, which spilled to tempdb.
DECLARE @CampaignId int = 14;
SELECT c.LastName, c.FirstName, d.SendDate, d.Opened, d.Clicked
FROM Marketing.Delivery AS d
JOIN Contact.Contact AS c ON c.ContactId = d.ContactId
WHERE d.CampaignId = @CampaignId
ORDER BY c.LastName, c.FirstName;
GO
-- 2. The same query compiled with the value of the variable: OPTION (RECOMPILE) compiles
--    the statement at each run, when the variable has its value. The estimate is right,
--    the plan changes, and the sort gets the memory it needs.
DECLARE @CampaignId int = 14;
SELECT c.LastName, c.FirstName, d.SendDate, d.Opened, d.Clicked
FROM Marketing.Delivery AS d
JOIN Contact.Contact AS c ON c.ContactId = d.ContactId
WHERE d.CampaignId = @CampaignId
ORDER BY c.LastName, c.FirstName
OPTION (RECOMPILE);
GO
SET STATISTICS IO, TIME OFF;
GO
-- What the cache says of query 1: the memory granted and used at its last run, in KB,
-- and the pages it spilled to tempdb. Query 2 is not in the cache: a statement compiled
-- with OPTION (RECOMPILE) does not keep its plan.
SELECT qs.execution_count, qs.last_grant_kb, qs.last_used_grant_kb, qs.last_spills
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS t
CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
WHERE t.text LIKE N'-- 1. The query of clip 3.3%'
  AND pa.attribute = N'dbid' AND CONVERT(int, pa.value) = DB_ID();
GO
-- 3. A warning that costs nothing: a conversion in the SELECT list. The plan warns that it
--    may affect the cardinality estimate, but no estimate depends on this column.
SELECT ContactId, LastName + ' ' + CAST(ContactId AS varchar(10)) AS Label
FROM Contact.Contact
WHERE LastName = 'Wagner';
GO
