-- ci: skip (two sessions: run 2a-window-1.sql first, then this one within five seconds)
-- Module D7 exercise, window 2: the tracking of the newsletter records the click of the
-- same reader, then stamps the campaign with the date of its last activity, kept in its
-- name by the marketing team.
USE PachadataTraining;
SET NOCOUNT ON;
SELECT @@SPID AS SessionId;
BEGIN TRANSACTION;
UPDATE Marketing.Delivery
SET Opened = 1, Clicked = 1
WHERE DeliveryId = 3779791;

WAITFOR DELAY '00:00:05';

UPDATE Marketing.Campaign
SET Name = N'Lettre PachaData septembre 2026 (clics au 18/10)'
WHERE CampaignId = 36;
COMMIT;
SELECT 'window 2 committed' AS Result;
