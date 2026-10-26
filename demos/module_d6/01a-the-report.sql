-- Clip D6.1: the report of the newsletter, for the September letter and for the November one.
-- Runs on the lab, in one session, after 00-setup.sql. Reads only.
USE PachadataTraining;
SET NOCOUNT ON;
GO
SET STATISTICS IO, TIME ON;
GO
-- The September letter (campaign 36), sent before the statistics were last computed.
EXEC Marketing.GetLetterResults @CampaignId = 36;
GO
-- The November letter, sent by 00-setup.sql.
EXEC Marketing.GetLetterResults @CampaignId = 17391;
GO
SET STATISTICS IO, TIME OFF;
GO
-- Both letters went to the same 107,994 contacts.
SELECT CampaignId, COUNT(*) AS Deliveries
FROM Marketing.Delivery
WHERE CampaignId IN (36, 17391)
GROUP BY CampaignId;
GO
