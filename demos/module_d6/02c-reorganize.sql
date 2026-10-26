-- Clip D6.2: ix_Delivery_ContactId reorganized, with what it costs in time and in log.
-- Runs on the lab, in one session, after 02b-fragmentation-cost.sql. Lasts about 25 seconds.
-- The database is in simple recovery: the CHECKPOINT empties the log before the measure.
USE PachadataTraining;
SET NOCOUNT ON;
GO
CHECKPOINT;
SELECT used_log_space_in_bytes / 1048576 AS LogUsedMB FROM sys.dm_db_log_space_usage;
GO
SET STATISTICS TIME ON;
ALTER INDEX ix_Delivery_ContactId ON Marketing.Delivery REORGANIZE;
SET STATISTICS TIME OFF;
GO
SELECT used_log_space_in_bytes / 1048576 AS LogUsedMB FROM sys.dm_db_log_space_usage;
GO
SELECT s.page_count, CAST(s.avg_fragmentation_in_percent AS decimal(5, 1)) AS FragmentationPct,
       CAST(s.avg_page_space_used_in_percent AS decimal(5, 1)) AS PageDensityPct
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'Marketing.Delivery'),
     INDEXPROPERTY(OBJECT_ID(N'Marketing.Delivery'), N'ix_Delivery_ContactId', 'IndexId'), NULL, 'SAMPLED') AS s
WHERE s.index_level = 0;
-- A reorganization does not touch the statistic of the index.
SELECT p.last_updated, p.rows, p.rows_sampled, p.modification_counter
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Marketing.Delivery') AND s.name = N'ix_Delivery_ContactId';
GO
