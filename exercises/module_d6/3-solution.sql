-- Exercise of module D6, solution. Runs on the lab, after 1-start.sql and 2-load.sql. Part 3
-- ends with a pause and a resume played from two sessions; alone, the guarded block of the
-- second session does nothing. The last lines drop ExoMaintenance.
-- ONLINE and RESUMABLE need the Enterprise or Developer edition.
USE ExoMaintenance;
GO
SET NOCOUNT ON;
------------------------------------------------------------------------------------------
-- Part 1. The statistic of the execution time
------------------------------------------------------------------------------------------
-- 1. 30,000 modifications since the creation of the index. The threshold of the table is
--    SQRT(1000 x 1,413,356) = 37,594 (the old rule, 500 + 20 %, would wait for 283,171).
SELECT p.rows, p.rows_sampled, p.steps, p.modification_counter, p.last_updated,
       CAST(SQRT(1000.0 * p.rows) AS int) AS Threshold, CAST(500 + 0.2 * p.rows AS int) AS OldThreshold
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'dbo.Trade') AND s.name = N'IX_Trade_ExecutedAt';
SELECT TOP (1) range_high_key AS LastStep
FROM sys.dm_db_stats_histogram(OBJECT_ID(N'dbo.Trade'), INDEXPROPERTY(OBJECT_ID(N'dbo.Trade'), N'IX_Trade_ExecutedAt', 'IndexId'))
ORDER BY step_number DESC;
GO
-- 2. The trades of March 6, all after the last step. Measured in the actual plan: 9,000 rows
--    estimated, 30 % of the 30,000 modifications, for 30,000; a clustered index scan.
--    An equality beyond the histogram would take density x modifications instead (clip
--    D6.1); a range takes a fixed share of the modifications: 30 % for >=, 9 % for a range
--    closed on both sides.
SET STATISTICS IO ON;
SELECT SUM(Quantity * Price) AS Amount FROM dbo.Trade WHERE ExecutedAt >= '20250306' OPTION (RECOMPILE);
SET STATISTICS IO OFF;
GO
-- 3. 7,593 trades more: the counter stops one below the threshold, and the statistic does
--    not move. Measured: 11,277.9 rows estimated, still 30 % of the modifications, for 37,593.
INSERT INTO dbo.Trade (TradeId, StrategyId, VenueId, InstrumentId, Side, Quantity, Price, ExecutedAt, ExternalId)
SELECT TOP (7593) TradeId, StrategyId, VenueId, InstrumentId, Side, Quantity, Price, ExecutedAt, ExternalId
FROM LuminaQuant.dbo.Trade
WHERE TradeId > (SELECT MAX(TradeId) FROM dbo.Trade)
ORDER BY TradeId;
GO
SELECT SUM(Quantity * Price) AS Amount FROM dbo.Trade WHERE ExecutedAt >= '20250306' OPTION (RECOMPILE);
SELECT p.rows, p.rows_sampled, p.modification_counter, p.last_updated
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'dbo.Trade') AND s.name = N'IX_Trade_ExecutedAt';
GO
-- 4. One more trade: the counter reaches the threshold, and the next compilation recomputes
--    the statistic before using it, on a sample (135,166 rows of 1,450,950). Measured: 42,030
--    rows estimated for 37,594: March 6 is now in the histogram.
INSERT INTO dbo.Trade (TradeId, StrategyId, VenueId, InstrumentId, Side, Quantity, Price, ExecutedAt, ExternalId)
SELECT TOP (1) TradeId, StrategyId, VenueId, InstrumentId, Side, Quantity, Price, ExecutedAt, ExternalId
FROM LuminaQuant.dbo.Trade
WHERE TradeId > (SELECT MAX(TradeId) FROM dbo.Trade)
ORDER BY TradeId;
GO
SELECT SUM(Quantity * Price) AS Amount FROM dbo.Trade WHERE ExecutedAt >= '20250306' OPTION (RECOMPILE);
SELECT p.rows, p.rows_sampled, p.modification_counter, p.last_updated
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'dbo.Trade') AND s.name = N'IX_Trade_ExecutedAt';
GO
------------------------------------------------------------------------------------------
-- Part 2. Missing indexes, unused index
------------------------------------------------------------------------------------------
-- 1. The suggestions of the database, by score. Read them first: a rebuild of an index of
--    the table, like the creation of an index, removes them all (measured; a reorganization
--    leaves them). The first two start with StrategyId; the fourth comes from the query of
--    part 1.
SELECT d.equality_columns, d.inequality_columns, d.included_columns, s.user_seeks,
       CAST(s.user_seeks * s.avg_total_user_cost * s.avg_user_impact / 100 AS decimal(12, 1)) AS Score
FROM sys.dm_db_missing_index_details AS d
JOIN sys.dm_db_missing_index_groups AS g ON g.index_handle = d.index_handle
JOIN sys.dm_db_missing_index_group_stats AS s ON s.group_handle = g.index_group_handle
WHERE d.database_id = DB_ID()
ORDER BY Score DESC;
GO
-- 2. Before: the first two reports scan the table.
SET STATISTICS IO ON;
SELECT SUM(Quantity) AS Volume FROM dbo.Trade WHERE StrategyId = 9 AND VenueId = 3;
SELECT SUM(Quantity * Price) AS Amount FROM dbo.Trade WHERE StrategyId = 4 AND InstrumentId > 10 AND Side = 'B';
SET STATISTICS IO OFF;
GO
-- 3. One index for the first two suggestions: StrategyId then VenueId in the key (the
--    equalities of the first report), the other columns included. The second report seeks on
--    StrategyId and filters Side and InstrumentId in the leaves. The third suggestion, on
--    VenueId and Quantity, would serve a report run twice: it is left out.
CREATE INDEX IX_Trade_StrategyId_VenueId ON dbo.Trade (StrategyId, VenueId)
INCLUDE (Side, InstrumentId, Quantity, Price);
GO
SET STATISTICS IO ON;
SELECT SUM(Quantity) AS Volume FROM dbo.Trade WHERE StrategyId = 9 AND VenueId = 3;
SELECT SUM(Quantity * Price) AS Amount FROM dbo.Trade WHERE StrategyId = 4 AND InstrumentId > 10 AND Side = 'B';
SET STATISTICS IO OFF;
-- Creating an index on the table removed all its suggestions, the third one included.
SELECT COUNT(*) AS SuggestionsLeft FROM sys.dm_db_missing_index_details WHERE database_id = DB_ID();
GO
-- 4. The usage of the indexes. IX_Trade_ExternalId: 30,002 updates, one per insert
--    statement (the 30,000 of 2-load.sql and the two of part 1), and no read.
SELECT i.name AS IndexName, u.user_seeks, u.user_scans, u.user_lookups, u.user_updates
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_usage_stats AS u
    ON u.database_id = DB_ID() AND u.object_id = i.object_id AND u.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'dbo.Trade')
ORDER BY i.index_id;
SELECT sqlserver_start_time FROM sys.dm_os_sys_info;
GO
-- 5. Disabled rather than dropped: the definition stays, the pages are freed, the writes no
--    longer maintain it. If a monthly job turns out to need it, a rebuild brings it back.
ALTER INDEX IX_Trade_ExternalId ON dbo.Trade DISABLE;
SELECT i.name AS IndexName, i.is_disabled, ISNULL(SUM(ps.used_page_count), 0) AS UsedPages
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_partition_stats AS ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'dbo.Trade') AND i.name = N'IX_Trade_ExternalId'
GROUP BY i.name, i.is_disabled;
GO
------------------------------------------------------------------------------------------
-- Part 3. The fragmentation of the price index
------------------------------------------------------------------------------------------
-- 1. The leaf pages allocated during the inserts, and the state of the leaves. The price is
--    not ascending: the one-by-one inserts land all over IX_Trade_Price and split its full
--    pages, while IX_Trade_ExecutedAt and PK_Trade add their pages at the end.
--    IX_Trade_StrategyId_VenueId, created after the inserts, is compact.
SELECT i.name AS IndexName, o.leaf_insert_count, o.leaf_allocation_count
FROM sys.dm_db_index_operational_stats(DB_ID(), OBJECT_ID(N'dbo.Trade'), NULL, NULL) AS o
JOIN sys.indexes AS i ON i.object_id = o.object_id AND i.index_id = o.index_id
ORDER BY i.index_id;
SELECT i.name AS IndexName, s.page_count,
       CAST(s.avg_fragmentation_in_percent AS decimal(5, 1)) AS FragmentationPct,
       CAST(s.avg_page_space_used_in_percent AS decimal(5, 1)) AS PageDensityPct
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'dbo.Trade'), NULL, NULL, 'SAMPLED') AS s
JOIN sys.indexes AS i ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE s.index_level = 0
ORDER BY i.index_id;
GO
-- 2. Reorganized: compacted in place, by short transactions, on one thread. The statistic of
--    the index is not recomputed.
CHECKPOINT;
SELECT used_log_space_in_bytes / 1048576 AS LogUsedMB FROM sys.dm_db_log_space_usage;
SET STATISTICS TIME ON;
ALTER INDEX IX_Trade_Price ON dbo.Trade REORGANIZE;
SET STATISTICS TIME OFF;
SELECT used_log_space_in_bytes / 1048576 AS LogUsedMB FROM sys.dm_db_log_space_usage;
SELECT s.page_count, CAST(s.avg_fragmentation_in_percent AS decimal(5, 1)) AS FragmentationPct,
       CAST(s.avg_page_space_used_in_percent AS decimal(5, 1)) AS PageDensityPct
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'dbo.Trade'),
     INDEXPROPERTY(OBJECT_ID(N'dbo.Trade'), N'IX_Trade_Price', 'IndexId'), NULL, 'SAMPLED') AS s
WHERE s.index_level = 0;
SELECT p.rows, p.rows_sampled, p.modification_counter, p.last_updated
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'dbo.Trade') AND s.name = N'IX_Trade_Price';
GO
-- 3. Rebuilt online and resumable: a new tree, built by short transactions that a pause can
--    stop. The statistic is recomputed, but on a sample: a resumable rebuild does not read
--    every row for it, unlike a rebuild that is not resumable. The usage counters of the
--    index survive the rebuild.
CHECKPOINT;
SELECT used_log_space_in_bytes / 1048576 AS LogUsedMB FROM sys.dm_db_log_space_usage;
SET STATISTICS TIME ON;
ALTER INDEX IX_Trade_Price ON dbo.Trade REBUILD WITH (ONLINE = ON, RESUMABLE = ON, MAX_DURATION = 10 MINUTES);
SET STATISTICS TIME OFF;
SELECT used_log_space_in_bytes / 1048576 AS LogUsedMB FROM sys.dm_db_log_space_usage;
SELECT p.rows, p.rows_sampled, p.modification_counter, p.last_updated
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'dbo.Trade') AND s.name = N'IX_Trade_Price';
SELECT u.user_seeks, u.user_scans, u.user_updates
FROM sys.dm_db_index_usage_stats AS u
WHERE u.database_id = DB_ID() AND u.object_id = OBJECT_ID(N'dbo.Trade')
  AND u.index_id = INDEXPROPERTY(OBJECT_ID(N'dbo.Trade'), N'IX_Trade_Price', 'IndexId');
GO
-- 4. Pause and resume. Session 1: rebuild the clustered index, on one thread so that it
--    lasts a few seconds.
ALTER INDEX PK_Trade ON dbo.Trade REBUILD WITH (ONLINE = ON, RESUMABLE = ON, MAXDOP = 1);
GO
-- Session 1, if the pause was made: the command stops on error 1219 and the session is
-- disconnected; the operation stays paused and keeps its work.
-- Session 2, within a second of the start: the pause, the state, then the resume. The IF
-- tests make this block do nothing once the rebuild is over.
USE ExoMaintenance;
GO
IF EXISTS (SELECT * FROM sys.index_resumable_operations WHERE name = N'PK_Trade' AND state_desc = N'RUNNING')
    ALTER INDEX PK_Trade ON dbo.Trade PAUSE;
GO
SELECT name, state_desc, CAST(percent_complete AS decimal(5, 1)) AS PctDone, last_pause_time
FROM sys.index_resumable_operations;
GO
-- A paused operation keeps a partial copy of the index, and the writes maintain both:
-- resume it or abort it, never leave it paused.
IF EXISTS (SELECT * FROM sys.index_resumable_operations WHERE name = N'PK_Trade' AND state_desc = N'PAUSED')
    ALTER INDEX PK_Trade ON dbo.Trade RESUME;
GO
SELECT COUNT(*) AS OperationsLeft FROM sys.index_resumable_operations;
GO
-- Cleanup.
USE master;
GO
ALTER DATABASE ExoMaintenance SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE ExoMaintenance;
GO
