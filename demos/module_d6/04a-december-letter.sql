-- Clip D6.4: the December newsletter, a month after the statistic was recomputed by hand.
-- Runs on the lab, in one session, after the scripts of clip D6.3. Sends the letter with
-- Marketing.CreateCampaign and records its opens, like 00-setup.sql for November.
USE PachadataTraining;
SET NOCOUNT ON;
GO
DECLARE @CampaignId int;
EXEC Marketing.CreateCampaign @Name = 'Lettre PachaData décembre 2026', @SendDate = '20261201',
     @CampaignId = @CampaignId OUTPUT;
UPDATE Marketing.Delivery
SET Opened = 1,
    Clicked = CASE WHEN (ContactId * 7919) % 100 < 4 THEN 1 ELSE 0 END
WHERE CampaignId = @CampaignId AND (ContactId * 7919) % 100 < 24;
SELECT @CampaignId AS CampaignId, COUNT(*) AS Deliveries
FROM Marketing.Delivery WHERE CampaignId = @CampaignId;
GO
-- The report of the December letter.
SET STATISTICS IO, TIME ON;
EXEC Marketing.GetLetterResults @CampaignId = 17392;
SET STATISTICS IO, TIME OFF;
GO
-- The statistic of the index on CampaignId: 107,994 modifications since 01c, above the
-- threshold, and not recomputed.
SELECT s.name AS StatisticName, p.last_updated, p.rows, p.rows_sampled, p.modification_counter,
       CAST(SQRT(1000.0 * p.rows) AS bigint) AS Threshold
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Marketing.Delivery') AND s.name = N'ix_Delivery_CampaignId';
GO
