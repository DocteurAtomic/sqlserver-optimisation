-- ci: skip (two sessions: run this one, then 2b-window-2.sql in another window within
-- five seconds)
-- Module D7 exercise, window 1, after 1-start.sql: the marketing team corrects the name of
-- the September letter, then fixes by hand a delivery that a reader says she opened.
USE PachadataTraining;
SET NOCOUNT ON;
SELECT @@SPID AS SessionId;
BEGIN TRANSACTION;
UPDATE Marketing.Campaign
SET Name = N'Lettre PachaData de septembre 2026'
WHERE CampaignId = 36;

WAITFOR DELAY '00:00:05';

UPDATE Marketing.Delivery
SET Opened = 1
WHERE DeliveryId = 3779791;
COMMIT;
SELECT 'window 1 committed' AS Result;
