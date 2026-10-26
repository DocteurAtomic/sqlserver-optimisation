-- Clip V8.2: the memory grant feedback. A sort that receives a hundred times the memory it
-- uses (the varchar(max) prospects of module V1), a sort that spills to tempdb (the
-- campaign query of module 3), then a sort whose size changes with its parameter, with
-- and without the percentile mode of SQL Server 2022, and the persistence in the Query
-- Store. Runs on the lab, in one session, after 00-setup.sql. Creates the view
-- Tools.MemoryGrants; changes two database scoped configurations and sets them back.
-- Turn on the actual plan in SSMS (Ctrl+M): MemoryGrantInfo is in the properties of the
-- SELECT operator (GrantedMemory, LastRequestedMemory, IsMemoryGrantFeedbackAdjusted).
-- Measured on 2025 CU7, not explained: the second run of the campaign query (step 2)
-- receives the corrected grant only in a session that asks for the actual plan (SSMS with
-- Ctrl+M, or SET STATISTICS XML ON). Run by sqlcmd without it, the cached plan keeps its
-- 1,024 KB and spills again, although the Query Store already has the feedback; the
-- corrected grant then comes at the next compilation (step 4).
USE PachadataTraining;
GO
-- The memory granted to the three sorts at their last run and the memory they used, in KB,
-- with the pages they spilled to tempdb.
CREATE OR ALTER VIEW Tools.MemoryGrants
AS
SELECT CASE WHEN st.objectid = OBJECT_ID(N'Contact.ListProspectsByZip') THEN 'ListProspectsByZip'
            WHEN st.text LIKE N'%ProspectUS_MAX%' THEN 'varchar(max) sort'
            ELSE 'campaign sort' END AS Query,
       qs.execution_count, qs.last_grant_kb, qs.last_used_grant_kb, qs.last_spills
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE st.text NOT LIKE N'%dm_exec_query_stats%'
  AND qs.last_grant_kb > 0
  AND (st.objectid = OBJECT_ID(N'Contact.ListProspectsByZip')
       OR st.text LIKE N'%FROM Contact.ProspectUS_MAX%ORDER BY LastName, FirstName%'
       OR st.text LIKE N'%WHERE d.CampaignId = @CampaignId%ORDER BY c.LastName, c.FirstName%');
GO
-- 1. The sort of the 20,342 prospects of Arlington in varchar(max), from module V1: the
--    optimizer sizes each varchar(max) value at 4,000 bytes. First run, then second run.
--    The comments stay in batches of their own: two runs are the same query only if their
--    batches have the same text.
GO
DECLARE @FirstName varchar(max), @LastName varchar(max), @Email varchar(max);
SELECT @FirstName = FirstName, @LastName = LastName, @Email = Email
FROM Contact.ProspectUS_MAX
WHERE City = 'Arlington'
ORDER BY LastName, FirstName;
GO
SELECT * FROM Tools.MemoryGrants;
GO
DECLARE @FirstName varchar(max), @LastName varchar(max), @Email varchar(max);
SELECT @FirstName = FirstName, @LastName = LastName, @Email = Email
FROM Contact.ProspectUS_MAX
WHERE City = 'Arlington'
ORDER BY LastName, FirstName;
GO
SELECT * FROM Tools.MemoryGrants;
GO
-- 2. The query of clip 3.4: the campaign in a variable, 245 rows estimated for 107,994.
--    The sort receives the minimum and spills. First run, then second run.
GO
DECLARE @CampaignId int = 14;
DECLARE @LastName varchar(50), @FirstName varchar(50), @SendDate datetime2, @Opened bit;
SELECT @LastName = c.LastName, @FirstName = c.FirstName, @SendDate = d.SendDate, @Opened = d.Opened
FROM Marketing.Delivery AS d
JOIN Contact.Contact AS c ON c.ContactId = d.ContactId
WHERE d.CampaignId = @CampaignId
ORDER BY c.LastName, c.FirstName;
GO
SELECT * FROM Tools.MemoryGrants;
GO
DECLARE @CampaignId int = 14;
DECLARE @LastName varchar(50), @FirstName varchar(50), @SendDate datetime2, @Opened bit;
SELECT @LastName = c.LastName, @FirstName = c.FirstName, @SendDate = d.SendDate, @Opened = d.Opened
FROM Marketing.Delivery AS d
JOIN Contact.Contact AS c ON c.ContactId = d.ContactId
WHERE d.CampaignId = @CampaignId
ORDER BY c.LastName, c.FirstName;
GO
SELECT * FROM Tools.MemoryGrants;
GO
-- 3. What the Query Store kept: one row per plan corrected, feature_id = 2.
SELECT f.plan_id, f.feature_desc, f.state_desc, f.feedback_data
FROM sys.query_store_plan_feedback AS f
WHERE f.feature_id = 2;
GO
-- 4. The persistence: the procedure cache of the database is emptied, the campaign query
--    is compiled again, and its first run receives the corrected grant.
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
DECLARE @CampaignId int = 14;
DECLARE @LastName varchar(50), @FirstName varchar(50), @SendDate datetime2, @Opened bit;
SELECT @LastName = c.LastName, @FirstName = c.FirstName, @SendDate = d.SendDate, @Opened = d.Opened
FROM Marketing.Delivery AS d
JOIN Contact.Contact AS c ON c.ContactId = d.ContactId
WHERE d.CampaignId = @CampaignId
ORDER BY c.LastName, c.FirstName;
GO
SELECT * FROM Tools.MemoryGrants;
GO
-- 5. A sort whose size depends on the parameter: the prospects of all the zip codes that
--    start with 9 (about 75,000), then those of one zip code (a few dozen), in turn. With
--    the percentile mode (the default), the grant settles.
CREATE TABLE #Runs (Run int IDENTITY, Zip varchar(10), GrantKB bigint, UsedKB bigint, Spills bigint);
GO
EXEC Contact.ListProspectsByZip @Zip = '9%';
INSERT #Runs (Zip, GrantKB, UsedKB, Spills) SELECT '9%', last_grant_kb, last_used_grant_kb, last_spills FROM Tools.MemoryGrants WHERE Query = 'ListProspectsByZip';
EXEC Contact.ListProspectsByZip @Zip = '97355';
INSERT #Runs (Zip, GrantKB, UsedKB, Spills) SELECT '97355', last_grant_kb, last_used_grant_kb, last_spills FROM Tools.MemoryGrants WHERE Query = 'ListProspectsByZip';
GO 4
SELECT * FROM #Runs ORDER BY Run;
TRUNCATE TABLE #Runs;
GO
-- 6. The same alternation without the percentile mode, and without the persistence (which
--    would bring back what was learned above): each run receives the memory the previous
--    one needed, one step behind.
ALTER DATABASE SCOPED CONFIGURATION SET MEMORY_GRANT_FEEDBACK_PERCENTILE_GRANT = OFF;
ALTER DATABASE SCOPED CONFIGURATION SET MEMORY_GRANT_FEEDBACK_PERSISTENCE = OFF;
EXEC sys.sp_recompile N'Contact.ListProspectsByZip';
GO
EXEC Contact.ListProspectsByZip @Zip = '9%';
INSERT #Runs (Zip, GrantKB, UsedKB, Spills) SELECT '9%', last_grant_kb, last_used_grant_kb, last_spills FROM Tools.MemoryGrants WHERE Query = 'ListProspectsByZip';
EXEC Contact.ListProspectsByZip @Zip = '97355';
INSERT #Runs (Zip, GrantKB, UsedKB, Spills) SELECT '97355', last_grant_kb, last_used_grant_kb, last_spills FROM Tools.MemoryGrants WHERE Query = 'ListProspectsByZip';
GO 4
SELECT * FROM #Runs ORDER BY Run;
DROP TABLE #Runs;
GO
ALTER DATABASE SCOPED CONFIGURATION SET MEMORY_GRANT_FEEDBACK_PERCENTILE_GRANT = ON;
ALTER DATABASE SCOPED CONFIGURATION SET MEMORY_GRANT_FEEDBACK_PERSISTENCE = ON;
GO
