-- Clip V8.1: the decisions put off until execution. The table variable of module V6 at
-- compatibility level 170, with and without the deferred compilation of SQL Server 2019;
-- the same table variable without the filter; the interleaved execution of a
-- multi-statement function; an adaptive join. Runs on the lab, in one session, after
-- 00-setup.sql. Changes two database scoped configurations and sets them back; empties the
-- procedure cache of this database only. Turn on the actual plan in SSMS (Ctrl+M).
-- Step 3 lasts about 6 seconds.
USE PachadataTraining;
GO
SET NOCOUNT ON;
GO
-- 1. Step 1 of 03-temp-tables.sql of module V6: all the contacts in a table variable, then
--    the deliveries of the contacts of company 1050 (3,218 contacts). The database is at
--    level 170: the deferred compilation of table variables is on.
DECLARE @Contacts TABLE (ContactId int NOT NULL PRIMARY KEY, CompanyId int NULL);
INSERT @Contacts (ContactId, CompanyId)
SELECT ContactId, CompanyId FROM Contact.Contact;

SET STATISTICS IO, TIME ON;
SELECT COUNT(*) AS Deliveries, SUM(CAST(d.Opened AS int)) AS Opened
FROM @Contacts AS t
JOIN Marketing.Delivery AS d ON d.ContactId = t.ContactId
WHERE t.CompanyId = 1050;
SET STATISTICS IO, TIME OFF;
GO
-- 2. The same batch with the deferred compilation turned off, as before SQL Server 2019:
--    the table variable is estimated at one row. The plan and the reads do not change.
ALTER DATABASE SCOPED CONFIGURATION SET DEFERRED_COMPILATION_TV = OFF;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
DECLARE @Contacts TABLE (ContactId int NOT NULL PRIMARY KEY, CompanyId int NULL);
INSERT @Contacts (ContactId, CompanyId)
SELECT ContactId, CompanyId FROM Contact.Contact;

SET STATISTICS IO, TIME ON;
SELECT COUNT(*) AS Deliveries, SUM(CAST(d.Opened AS int)) AS Opened
FROM @Contacts AS t
JOIN Marketing.Delivery AS d ON d.ContactId = t.ContactId
WHERE t.CompanyId = 1050;
SET STATISTICS IO, TIME OFF;
GO
-- 3. What the deferred compilation does correct: the number of rows. The contacts that
--    belong to a company (105,580), all joined to their deliveries. Still turned off first,
--    then on again.
DECLARE @Contacts TABLE (ContactId int NOT NULL PRIMARY KEY, CompanyId int NULL);
INSERT @Contacts (ContactId, CompanyId)
SELECT ContactId, CompanyId FROM Contact.Contact WHERE CompanyId IS NOT NULL;

SET STATISTICS IO, TIME ON;
SELECT COUNT(*) AS Deliveries, SUM(CAST(d.Opened AS int)) AS Opened
FROM @Contacts AS t
JOIN Marketing.Delivery AS d ON d.ContactId = t.ContactId;
SET STATISTICS IO, TIME OFF;
GO
ALTER DATABASE SCOPED CONFIGURATION SET DEFERRED_COMPILATION_TV = ON;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
DECLARE @Contacts TABLE (ContactId int NOT NULL PRIMARY KEY, CompanyId int NULL);
INSERT @Contacts (ContactId, CompanyId)
SELECT ContactId, CompanyId FROM Contact.Contact WHERE CompanyId IS NOT NULL;

SET STATISTICS IO, TIME ON;
SELECT COUNT(*) AS Deliveries, SUM(CAST(d.Opened AS int)) AS Opened
FROM @Contacts AS t
JOIN Marketing.Delivery AS d ON d.ContactId = t.ContactId;
SET STATISTICS IO, TIME OFF;
GO
-- 4. The interleaved execution of SQL Server 2017: the multi-statement function
--    dbo.fnDateTable (one row per day, 6,209 days) is run during the optimization, and
--    its actual number of rows replaces the fixed guess of 100. The actual plan says
--    IsInterleavedExecuted. Then the same query with the feature turned off.
SET STATISTICS IO ON;
SELECT COUNT(*) AS Sessions, SUM(s.Price) AS Revenue
FROM dbo.fnDateTable('20110101', '20271231', 'd') AS d
JOIN Course.Session AS s ON s.StartDate = d.Date;
SET STATISTICS IO OFF;
GO
ALTER DATABASE SCOPED CONFIGURATION SET INTERLEAVED_EXECUTION_TVF = OFF;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
SET STATISTICS IO ON;
SELECT COUNT(*) AS Sessions, SUM(s.Price) AS Revenue
FROM dbo.fnDateTable('20110101', '20271231', 'd') AS d
JOIN Course.Session AS s ON s.StartDate = d.Date;
SET STATISTICS IO OFF;
GO
ALTER DATABASE SCOPED CONFIGURATION SET INTERLEAVED_EXECUTION_TVF = ON;
GO
-- 5. The adaptive join: the targeting report of module V3, statistics intact. The actual
--    plan has an Adaptive Join, with its threshold (AdaptiveThresholdRows) and the join it
--    ran (ActualJoinType). Then the report compiled first for one week of birth dates: the
--    optimizer chooses nested loops, without an adaptive join, and the wide range that
--    follows reuses them.
SET ARITHABORT ON;
SET STATISTICS IO ON;
EXEC Marketing.GetCampaignTargets @Gender = 'F', @BornFrom = '19700101', @BornBefore = '19930101';
SET STATISTICS IO OFF;
GO
EXEC sys.sp_recompile N'Marketing.GetCampaignTargets';
GO
SET ARITHABORT ON;
SET STATISTICS IO ON;
EXEC Marketing.GetCampaignTargets @Gender = 'F', @BornFrom = '19700101', @BornBefore = '19700108';
EXEC Marketing.GetCampaignTargets @Gender = 'F', @BornFrom = '19700101', @BornBefore = '19930101';
SET STATISTICS IO OFF;
GO
EXEC sys.sp_recompile N'Marketing.GetCampaignTargets';
GO
