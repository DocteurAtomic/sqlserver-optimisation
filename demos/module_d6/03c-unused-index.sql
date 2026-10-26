-- Clip D6.3: ix_Delivery_ContactId, unused during the day. What it costs to keep, and what
-- it costs to lose. Runs on the lab, in one session, after 03b-business-day.sql. Disables
-- the index, then rebuilds it, which enables it again.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. What the index costs: its size. 02a-physical-stats.sql measured what one newsletter
--    does to it, page splits all over the index.
SELECT i.name AS IndexName, SUM(ps.used_page_count) AS UsedPages, SUM(ps.used_page_count) * 8 / 1024 AS UsedMB
FROM sys.indexes AS i
JOIN sys.dm_db_partition_stats AS ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'Marketing.Delivery')
GROUP BY i.index_id, i.name
ORDER BY i.index_id;
GO
-- 2. The company page of the CRM, which the sales team opens before meeting a client: the
--    last letter of each contact of the company. With the index.
SET STATISTICS IO, TIME ON;
EXEC Demo.LastDeliveryByContact_Fixed @CompanyId = 36;
SET STATISTICS IO, TIME OFF;
GO
-- 3. The index disabled: its definition stays in the metadata, its pages are freed, and
--    the writes stop maintaining it.
ALTER INDEX ix_Delivery_ContactId ON Marketing.Delivery DISABLE;
GO
SET STATISTICS IO, TIME ON;
EXEC Demo.LastDeliveryByContact_Fixed @CompanyId = 36;
SET STATISTICS IO, TIME OFF;
GO
-- 4. Enabling it again is rebuilding it.
ALTER INDEX ix_Delivery_ContactId ON Marketing.Delivery REBUILD WITH (ONLINE = ON);
GO
SELECT name, is_disabled FROM sys.indexes
WHERE object_id = OBJECT_ID(N'Marketing.Delivery') AND name = N'ix_Delivery_ContactId';
GO
