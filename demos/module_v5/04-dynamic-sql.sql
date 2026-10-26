-- Clip V5.4: dynamic SQL. The query of the sender built by concatenation, then passed to
-- sp_executesql with a parameter: what each leaves in the cache, what each costs in
-- compilations, the injection that concatenation opens, and the sniffing that the parameter
-- brings back. Runs on the lab, in one session, after 03-remedies.sql. It creates
-- Marketing.SearchCampaigns, a search of the back office written by concatenation, and drops
-- it at the end. ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE empties the plans
-- of this database only.
USE PachadataTraining;
GO
SET NOCOUNT ON;
SET ARITHABORT OFF;
CREATE TABLE #Recipients (LastName varchar(50), FirstName varchar(50), Email varchar(150),
                          SendDate datetime2, Opened bit);
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
-- 1. One hundred evaluations, the value written in the text of the query.
DECLARE @Cpu int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID),
        @CampaignId int = 17291, @sql nvarchar(max);
WHILE @CampaignId <= 17390
BEGIN
    SET @sql = N'SELECT c.LastName, c.FirstName, c.Email, e.SendDate, e.Opened
FROM Marketing.Delivery AS e
JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
WHERE e.CampaignId = ' + CAST(@CampaignId AS nvarchar(11)) + N';';
    INSERT INTO #Recipients EXEC (@sql);
    SET @CampaignId += 1;
END;
SELECT 'concatenated' AS Query,
       (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID) - @Cpu AS CpuMs;
GO
-- 2. The same hundred, the value passed as a parameter of sp_executesql.
DECLARE @Cpu int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID),
        @CampaignId int = 17291,
        @sql nvarchar(max) = N'SELECT c.LastName, c.FirstName, c.Email, e.SendDate, e.Opened
FROM Marketing.Delivery AS e
JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
WHERE e.CampaignId = @CampaignId;';
WHILE @CampaignId <= 17390
BEGIN
    INSERT INTO #Recipients EXEC sys.sp_executesql @sql, N'@CampaignId int',
                                                   @CampaignId = @CampaignId;
    SET @CampaignId += 1;
END;
SELECT 'parameterized' AS Query,
       (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID) - @Cpu AS CpuMs;
GO
-- 3. What each left in the cache.
SELECT cp.objtype, COUNT(*) AS Plans, SUM(cp.usecounts) AS Uses,
       SUM(cp.size_in_bytes) / 1024 AS SizeKB
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
WHERE st.dbid = DB_ID()
  AND (st.text LIKE N'SELECT c.LastName, c.FirstName%'
       OR st.text LIKE N'(@CampaignId int)SELECT c.LastName, c.FirstName%')
GROUP BY cp.objtype;
GO
DROP TABLE #Recipients;
GO
-- 4. The search of the back office, written by concatenation.
CREATE OR ALTER PROCEDURE Marketing.SearchCampaigns @Name nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql nvarchar(max) = N'SELECT CampaignId, CampaignType, Name, SendDate '
        + N'FROM Marketing.Campaign WHERE Name LIKE N''' + @Name + N'%'' ORDER BY SendDate DESC;';
    EXEC (@sql);
END;
GO
EXEC Marketing.SearchCampaigns @Name = N'Lettre PachaData sept';
GO
-- The same search, with a name typed by someone who knows how the query is built.
EXEC Marketing.SearchCampaigns
     @Name = N''' UNION ALL SELECT principal_id, NULL, name COLLATE DATABASE_DEFAULT, NULL FROM sys.sql_logins --';
GO
-- 5. The search rewritten with sp_executesql: the value never enters the text.
CREATE OR ALTER PROCEDURE Marketing.SearchCampaigns @Name nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    EXEC sys.sp_executesql N'SELECT CampaignId, CampaignType, Name, SendDate
FROM Marketing.Campaign
WHERE Name LIKE @Name + N''%''
ORDER BY SendDate DESC;', N'@Name nvarchar(100)', @Name = @Name;
END;
GO
EXEC Marketing.SearchCampaigns @Name = N'Lettre PachaData sept';
EXEC Marketing.SearchCampaigns
     @Name = N''' UNION ALL SELECT principal_id, NULL, name COLLATE DATABASE_DEFAULT, NULL FROM sys.sql_logins --';
GO
DROP PROCEDURE Marketing.SearchCampaigns;
GO
-- 6. The parameterized query has one plan, compiled for the first value: the letter.
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
DECLARE @sql nvarchar(max) = N'SELECT c.LastName, c.FirstName, c.Email, e.SendDate, e.Opened
FROM Marketing.Delivery AS e
JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
WHERE e.CampaignId = @CampaignId;';
EXEC sys.sp_executesql @sql, N'@CampaignId int', @CampaignId = 36;
SET STATISTICS IO, TIME ON;
EXEC sys.sp_executesql @sql, N'@CampaignId int', @CampaignId = 17389;
SET STATISTICS IO, TIME OFF;
GO
-- 7. The compilation of sp_executesql serialized, SQL Server 2025: off by default.
SELECT name, value, is_value_default
FROM sys.database_scoped_configurations
WHERE name = N'OPTIMIZED_SP_EXECUTESQL';
GO
