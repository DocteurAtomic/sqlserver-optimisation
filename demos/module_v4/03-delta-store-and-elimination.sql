-- Clip V4.3: the delta store and segment elimination. A load of 102,399 rows, then of
-- 102,400, into an empty columnstore table; the bounds of the segments of the copy, the
-- segments a filter skips, and the ORDER clause, offline then online. Runs on the lab, in
-- one session, after 02-batch-mode.sql. Lasts about seven minutes: the two ordered
-- rebuilds of 24 million rows take two and five minutes. Creates and drops dbo.TradeLoad;
-- rebuilds dbo.TradeColumnstore.
USE LuminaQuant;
GO
-- 1. An empty table with the columns of the copy, in a clustered columnstore index.
DROP TABLE IF EXISTS dbo.TradeLoad;
CREATE TABLE dbo.TradeLoad (
    TradeId    bigint        NOT NULL,
    ExecutedAt datetime2(3)  NOT NULL,
    VenueId    int           NOT NULL,
    Side       char(1)       NOT NULL,
    Quantity   decimal(18,8) NOT NULL,
    Price      decimal(18,8) NOT NULL,
    INDEX ccix_TradeLoad CLUSTERED COLUMNSTORE
);
GO
-- 2. One insert of 102,399 rows: one row under the threshold.
INSERT INTO dbo.TradeLoad (TradeId, ExecutedAt, VenueId, Side, Quantity, Price)
SELECT TOP (102399) TradeId, ExecutedAt, VenueId, Side, Quantity, Price
FROM dbo.Trade ORDER BY TradeId;
SELECT row_group_id, state_desc, total_rows, trim_reason_desc
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID(N'dbo.TradeLoad');
GO
-- 3. The same with one more row: 102,400.
TRUNCATE TABLE dbo.TradeLoad;
INSERT INTO dbo.TradeLoad (TradeId, ExecutedAt, VenueId, Side, Quantity, Price)
SELECT TOP (102400) TradeId, ExecutedAt, VenueId, Side, Quantity, Price
FROM dbo.Trade ORDER BY TradeId;
SELECT row_group_id, state_desc, total_rows, trim_reason_desc
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID(N'dbo.TradeLoad');
GO
DROP TABLE dbo.TradeLoad;
GO
-- 4. The bounds of the segments of ExecutedAt in the copy. The values are internal
--    integers that grow with the date.
SELECT s.segment_id, s.row_count, s.min_data_id, s.max_data_id
FROM sys.column_store_segments AS s
JOIN sys.partitions AS p ON p.partition_id = s.partition_id
JOIN sys.columns AS c ON c.object_id = p.object_id AND c.column_id = s.column_id
WHERE p.object_id = OBJECT_ID(N'dbo.TradeColumnstore') AND c.name = N'ExecutedAt'
ORDER BY s.segment_id;
GO
SET STATISTICS IO ON;
GO
-- 5. One day of trades, then one venue: the segments read and skipped are in the Messages tab.
SELECT VenueId, COUNT_BIG(*) AS Trades
FROM dbo.TradeColumnstore
WHERE ExecutedAt >= '20250303' AND ExecutedAt < '20250304'
GROUP BY VenueId;
SELECT CAST(ExecutedAt AS date) AS TradeDate, COUNT_BIG(*) AS Trades
FROM dbo.TradeColumnstore
WHERE VenueId = 3
GROUP BY CAST(ExecutedAt AS date);
GO
SET STATISTICS IO OFF;
GO
-- 6. Is the index ordered? column_store_order_ordinal is 0 for every column.
SELECT c.name AS ColumnName, ic.column_store_order_ordinal
FROM sys.index_columns AS ic
JOIN sys.columns AS c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE ic.object_id = OBJECT_ID(N'dbo.TradeColumnstore');
GO
-- 7. The ORDER clause (SQL Server 2022 and later), offline, on one thread. About two
--    minutes.
CREATE CLUSTERED COLUMNSTORE INDEX ccix_TradeColumnstore ON dbo.TradeColumnstore
    ORDER (ExecutedAt)
    WITH (DROP_EXISTING = ON, MAXDOP = 1);
GO
SELECT has_vertipaq_optimization, COUNT(*) AS RowGroups
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID(N'dbo.TradeColumnstore')
GROUP BY has_vertipaq_optimization;
GO
SET STATISTICS IO ON;
GO
SELECT VenueId, COUNT_BIG(*) AS Trades
FROM dbo.TradeColumnstore
WHERE ExecutedAt >= '20250303' AND ExecutedAt < '20250304'
GROUP BY VenueId;
GO
SET STATISTICS IO OFF;
GO
-- 8. The same, online (SQL Server 2025: SQL Server 2022 refuses ONLINE with ORDER, error
--    10679). About five minutes; the sort spills to tempdb instead of stopping at its
--    memory grant.
CREATE CLUSTERED COLUMNSTORE INDEX ccix_TradeColumnstore ON dbo.TradeColumnstore
    ORDER (ExecutedAt)
    WITH (DROP_EXISTING = ON, MAXDOP = 1, ONLINE = ON);
GO
SET STATISTICS IO ON;
GO
SELECT VenueId, COUNT_BIG(*) AS Trades
FROM dbo.TradeColumnstore
WHERE ExecutedAt >= '20250303' AND ExecutedAt < '20250304'
GROUP BY VenueId;
GO
SET STATISTICS IO OFF;
GO
SELECT c.name AS ColumnName, ic.column_store_order_ordinal
FROM sys.index_columns AS ic
JOIN sys.columns AS c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE ic.object_id = OBJECT_ID(N'dbo.TradeColumnstore') AND ic.column_store_order_ordinal > 0;
GO
-- 9. What the online build changed besides the order: the size of each column, and the
--    VertiPaq optimization of the row groups (the reordering of the rows inside a row group
--    that the engine does to compress better).
SELECT SUM(a.used_pages) * 8 / 1024 AS UsedMB
FROM sys.partitions AS p
JOIN sys.allocation_units AS a ON a.container_id = p.partition_id
WHERE p.object_id = OBJECT_ID(N'dbo.TradeColumnstore');
SELECT c.name AS ColumnName, SUM(s.on_disk_size) / 1024 AS SizeKB
FROM sys.column_store_segments AS s
JOIN sys.partitions AS p ON p.partition_id = s.partition_id
JOIN sys.columns AS c ON c.object_id = p.object_id AND c.column_id = s.column_id
WHERE p.object_id = OBJECT_ID(N'dbo.TradeColumnstore')
GROUP BY c.name
ORDER BY SizeKB DESC;
SELECT has_vertipaq_optimization, COUNT(*) AS RowGroups
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID(N'dbo.TradeColumnstore')
GROUP BY has_vertipaq_optimization;
GO
