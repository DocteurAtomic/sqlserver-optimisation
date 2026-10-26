-- Exercise of module V2, start. Runs on the lab, in one session. It lasts a few seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. Creates the two procedures of the marketing back office the exercise works on:
--    - Marketing.GetContactDeliveries, the history of the e-mails sent to a contact, which
--      the contact page of the back office shows (part 1);
--    - Marketing.GetCampaignDeliveries, the e-mails of a campaign that were clicked, or not,
--      for the report of a newsletter (part 2).
-- 3. Gives the queries of the three parts.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
CREATE OR ALTER PROCEDURE Marketing.GetContactDeliveries
    @ContactId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT DeliveryId, CampaignId, SendDate, Opened, Clicked
    FROM Marketing.Delivery
    WHERE ContactId = @ContactId
    ORDER BY SendDate DESC;
END;
GO
CREATE OR ALTER PROCEDURE Marketing.GetCampaignDeliveries
    @CampaignId int,
    @Clicked    bit
AS
BEGIN
    SET NOCOUNT ON;
    SELECT DeliveryId, ContactId, SendDate
    FROM Marketing.Delivery
    WHERE CampaignId = @CampaignId
      AND Clicked = @Clicked;
END;
GO
-- Part 1. The history of contact 1234 (36 e-mails), as the contact page asks for it.
--   SET STATISTICS IO ON;
--   EXEC Marketing.GetContactDeliveries @ContactId = 1234;
--
-- Part 2. The clicks of the newsletter of September 2026 (campaign 36, 107,994 e-mails).
--   EXEC Marketing.GetCampaignDeliveries @CampaignId = 36, @Clicked = 1;
--
-- Part 3. The newsletter of October 2026: 107,994 e-mails recorded in one statement, inside
-- a transaction rolled back at the end. The log it writes, before and after your indexes:
--   BEGIN TRANSACTION;
--   INSERT INTO Marketing.Campaign (CampaignId, CampaignType, Name, SendDate, SessionId)
--   VALUES (100000, 'Letter', 'Lettre PachaData octobre 2026', '20261006', NULL);
--   INSERT INTO Marketing.Delivery (CampaignId, ContactId, SendDate, Opened, Clicked)
--   SELECT 100000, ContactId, DATEADD(day, 35, SendDate), 0, 0
--   FROM Marketing.Delivery WHERE CampaignId = 36;
--   SELECT database_transaction_log_bytes_used FROM sys.dm_tran_database_transactions
--   WHERE transaction_id = CURRENT_TRANSACTION_ID() AND database_id = DB_ID();
--   ROLLBACK TRANSACTION;
SELECT i.name AS IndexName, i.type_desc AS IndexType
FROM sys.indexes AS i
WHERE i.object_id = OBJECT_ID(N'Marketing.Delivery')
ORDER BY i.index_id;
