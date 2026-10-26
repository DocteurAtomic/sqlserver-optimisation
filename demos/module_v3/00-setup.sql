-- Module V3, setup. Runs on the lab, in one session, before the first clip of the module.
-- It lasts a few seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. The problem of the module: a maintenance script, written to "save compilation time",
--    turned AUTO_CREATE_STATISTICS off for the database and dropped the statistics the
--    optimizer had created by itself on Contact.Contact (the _WA_Sys_ ones). Only the
--    statistics of the two indexes of the table remain, on ContactId and LastName.
-- 3. The marketing team gets its targeting report, Marketing.GetCampaignTargets: the contacts
--    of one gender born in a range of years, with what they did with the e-mails already
--    sent to them. Gender and BirthDate are in no index, and now have no statistic: the
--    optimizer guesses how many contacts the filter keeps, and its guess is far too small.
--    It joins the deliveries by nested loops, with one Key Lookup per delivery.
--    Clip V3.4 tells it, and measures the report once AUTO_CREATE_STATISTICS is back on.
-- 4. Turns off the cardinality estimation feedback for expressions of SQL Server 2025
--    (CE_FEEDBACK_FOR_EXPRESSIONS = OFF) for the database. After a few runs of the report,
--    it learns that the estimate of the filter is wrong, changes the model assumption, and
--    the plan of the report changes in the middle of the module. Its memory, the cache
--    sys.dm_exec_ce_feedback_cache, is kept by database_id and survives the restore of
--    step 1. The restore of the next module turns it back on.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
ALTER DATABASE CURRENT SET AUTO_CREATE_STATISTICS OFF;
GO
ALTER DATABASE SCOPED CONFIGURATION SET CE_FEEDBACK_FOR_EXPRESSIONS = OFF;
GO
DECLARE @sql nvarchar(max) = N'';
SELECT @sql += N'DROP STATISTICS Contact.Contact.' + QUOTENAME(name) + N';'
FROM sys.stats
WHERE object_id = OBJECT_ID(N'Contact.Contact') AND auto_created = 1;
EXEC sys.sp_executesql @sql;
GO
CREATE OR ALTER PROCEDURE Marketing.GetCampaignTargets
    @Gender     char(1),
    @BornFrom   date,
    @BornBefore date
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.ContactId, c.LastName, c.FirstName,
           COUNT(*)                    AS Deliveries,
           SUM(CAST(d.Opened AS int))  AS Opened,
           SUM(CAST(d.Clicked AS int)) AS Clicked
    FROM Contact.Contact AS c
    JOIN Marketing.Delivery AS d ON d.ContactId = c.ContactId
    WHERE c.Gender = @Gender
      AND c.BirthDate >= @BornFrom
      AND c.BirthDate <  @BornBefore
    GROUP BY c.ContactId, c.LastName, c.FirstName;
END;
GO
SELECT name, is_auto_create_stats_on, is_auto_update_stats_on
FROM sys.databases
WHERE name = DB_NAME();
SELECT name, value
FROM sys.database_scoped_configurations
WHERE name = N'CE_FEEDBACK_FOR_EXPRESSIONS';
SELECT name AS StatisticName
FROM sys.stats
WHERE object_id = OBJECT_ID(N'Contact.Contact');
