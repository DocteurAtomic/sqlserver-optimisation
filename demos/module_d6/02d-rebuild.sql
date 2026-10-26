-- Clip D6.2: ix_Delivery_ContactId rebuilt online, with what it costs, and what it does to
-- the statistic of the index and to its usage counters.
-- Runs on the lab, in one session, after the second run of 02b-fragmentation-cost.sql.
-- ONLINE needs the Enterprise or Developer edition.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- The usage row of the index before the rebuild (the scans of 02b).
SELECT u.user_seeks, u.user_scans, u.user_updates, u.last_user_scan
FROM sys.dm_db_index_usage_stats AS u
WHERE u.database_id = DB_ID() AND u.object_id = OBJECT_ID(N'Marketing.Delivery')
  AND u.index_id = INDEXPROPERTY(OBJECT_ID(N'Marketing.Delivery'), N'ix_Delivery_ContactId', 'IndexId');
CHECKPOINT;
SELECT used_log_space_in_bytes / 1048576 AS LogUsedMB FROM sys.dm_db_log_space_usage;
GO
SET STATISTICS TIME ON;
ALTER INDEX ix_Delivery_ContactId ON Marketing.Delivery REBUILD WITH (ONLINE = ON);
SET STATISTICS TIME OFF;
GO
SELECT used_log_space_in_bytes / 1048576 AS LogUsedMB FROM sys.dm_db_log_space_usage;
GO
SELECT s.page_count, CAST(s.avg_fragmentation_in_percent AS decimal(5, 1)) AS FragmentationPct,
       CAST(s.avg_page_space_used_in_percent AS decimal(5, 1)) AS PageDensityPct,
       s.avg_record_size_in_bytes
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'Marketing.Delivery'),
     INDEXPROPERTY(OBJECT_ID(N'Marketing.Delivery'), N'ix_Delivery_ContactId', 'IndexId'), NULL, 'DETAILED') AS s
WHERE s.index_level = 0;
-- A rebuild recomputes the statistic of the index, on every row.
SELECT p.last_updated, p.rows, p.rows_sampled, p.modification_counter
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Marketing.Delivery') AND s.name = N'ix_Delivery_ContactId';
-- And the usage row of the index after the rebuild.
SELECT u.user_seeks, u.user_scans, u.user_updates, u.last_user_scan
FROM sys.dm_db_index_usage_stats AS u
WHERE u.database_id = DB_ID() AND u.object_id = OBJECT_ID(N'Marketing.Delivery')
  AND u.index_id = INDEXPROPERTY(OBJECT_ID(N'Marketing.Delivery'), N'ix_Delivery_ContactId', 'IndexId');
GO
