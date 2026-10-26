-- Clip D6.2: the fragmentation of the indexes of Marketing.Delivery after the November letter.
-- Runs on the lab, in one session, after the scripts of clip D6.1. Reads only.
-- At delivery, the three indexes are below 1 % of fragmentation and full: pk_Delivery 9,818
-- leaf pages, ix_Delivery_CampaignId 4,483, ix_Delivery_ContactId 5,321.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. LIMITED, the default: reads the level above the leaves, gives the fragmentation (the
--    share of leaf pages out of order) and the number of pages, not their fill.
SELECT i.name AS IndexName, s.page_count,
       CAST(s.avg_fragmentation_in_percent AS decimal(5, 1)) AS FragmentationPct,
       s.fragment_count, s.avg_page_space_used_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'Marketing.Delivery'), NULL, NULL, 'LIMITED') AS s
JOIN sys.indexes AS i ON i.object_id = s.object_id AND i.index_id = s.index_id
ORDER BY s.index_id;
GO
-- 2. SAMPLED: reads 1 % of the leaf pages of a large index (all of them under 10,000 pages)
--    and gives the page density, avg_page_space_used_in_percent.
SELECT i.name AS IndexName, s.page_count, s.record_count,
       CAST(s.avg_fragmentation_in_percent AS decimal(5, 1)) AS FragmentationPct,
       CAST(s.avg_page_space_used_in_percent AS decimal(5, 1)) AS PageDensityPct
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'Marketing.Delivery'), NULL, NULL, 'SAMPLED') AS s
JOIN sys.indexes AS i ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE s.index_level = 0
ORDER BY s.index_id;
GO
