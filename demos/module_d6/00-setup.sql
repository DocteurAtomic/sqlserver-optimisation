-- Module D6, setup. Runs on the lab, in one session, before the first clip of the module.
-- It lasts a few seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. The problem of the module: AUTO_UPDATE_STATISTICS is turned off for the database, as a
--    former administrator did "to stop the recompilations during the day". SQL Server keeps
--    counting the modifications of each statistic, but never updates one by itself.
-- 3. Creates Marketing.GetLetterResults, the report the marketing team runs a week after
--    each newsletter: deliveries, opens and clicks per business sector of the recipients.
-- 4. Sends the November newsletter with the procedure of the database,
--    Marketing.CreateCampaign: 107,994 deliveries of a new campaign, whose identifier comes
--    after the last step of the histogram of ix_Delivery_CampaignId. Then records a week of
--    opens and clicks (about 24 % and 4 %, the rates of the previous letters; a click always
--    implies an open, as in the rest of the table).
--    The report estimates a few rows for the new letter, joins by nested loops, and reads
--    about 840,000 pages instead of 13,000. Clip D6.4 tells why, and measures the fix.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
ALTER DATABASE CURRENT SET AUTO_UPDATE_STATISTICS OFF;
GO
CREATE OR ALTER PROCEDURE Marketing.GetLetterResults
    @CampaignId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT co.Sector,
           COUNT(*)                    AS Sent,
           SUM(CAST(d.Opened AS int))  AS Opened,
           SUM(CAST(d.Clicked AS int)) AS Clicked
    FROM Marketing.Delivery AS d
    JOIN Contact.Contact AS c ON c.ContactId = d.ContactId
    LEFT JOIN Contact.Company AS co ON co.CompanyId = c.CompanyId
    WHERE d.CampaignId = @CampaignId
    GROUP BY co.Sector
    ORDER BY Sent DESC;
END;
GO
SET NOCOUNT ON;
DECLARE @CampaignId int;
EXEC Marketing.CreateCampaign @Name = 'Lettre PachaData novembre 2026', @SendDate = '20261103',
     @CampaignId = @CampaignId OUTPUT;
-- A week of opens and clicks, deterministic.
UPDATE Marketing.Delivery
SET Opened = 1,
    Clicked = CASE WHEN (ContactId * 7919) % 100 < 4 THEN 1 ELSE 0 END
WHERE CampaignId = @CampaignId AND (ContactId * 7919) % 100 < 24;
SELECT c.CampaignId, c.Name, c.SendDate, COUNT(*) AS Deliveries,
       SUM(CAST(d.Opened AS int)) AS Opened, SUM(CAST(d.Clicked AS int)) AS Clicked
FROM Marketing.Campaign AS c
JOIN Marketing.Delivery AS d ON d.CampaignId = c.CampaignId
WHERE c.CampaignId = @CampaignId
GROUP BY c.CampaignId, c.Name, c.SendDate;
GO
SELECT name, is_auto_create_stats_on, is_auto_update_stats_on, compatibility_level
FROM sys.databases
WHERE name = DB_NAME();
GO
