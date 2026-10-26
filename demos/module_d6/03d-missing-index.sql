-- Clip D6.3: the two suggestions on Marketing.Delivery merged into the index that already
-- exists. Runs on the lab, in one session, after 03c-unused-index.sql. Rebuilds
-- ix_Delivery_CampaignId with three included columns; 00-setup.sql restores the database.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. Before: the report of the November letter, and the size of the index.
SET STATISTICS IO, TIME ON;
EXEC Marketing.GetLetterResults @CampaignId = 17391;
SET STATISTICS IO, TIME OFF;
SELECT SUM(used_page_count) AS UsedPages
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'Marketing.Delivery')
  AND index_id = INDEXPROPERTY(OBJECT_ID(N'Marketing.Delivery'), N'ix_Delivery_CampaignId', 'IndexId');
GO
-- 2. One index for both suggestions: the same key, the union of the included columns, in
--    place of the existing index rather than beside it.
CREATE INDEX ix_Delivery_CampaignId ON Marketing.Delivery (CampaignId)
INCLUDE (ContactId, Opened, Clicked)
WITH (DROP_EXISTING = ON, ONLINE = ON);
GO
-- 3. After.
SET STATISTICS IO, TIME ON;
EXEC Marketing.GetLetterResults @CampaignId = 17391;
SET STATISTICS IO, TIME OFF;
SELECT SUM(used_page_count) AS UsedPages
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'Marketing.Delivery')
  AND index_id = INDEXPROPERTY(OBJECT_ID(N'Marketing.Delivery'), N'ix_Delivery_CampaignId', 'IndexId');
-- 4. The suggestions of the table are gone, both of them.
SELECT COUNT(*) AS SuggestionsOnDelivery
FROM sys.dm_db_missing_index_details
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Marketing.Delivery');
GO
