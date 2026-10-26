-- Clip V4.1: column storage. The daily report measured, then a columnstore copy of the
-- columns it reads: its row groups, its size next to the rowstore index, the size of each
-- column, and the pages the same query reads on it. Runs on the lab, in one session, after
-- 00-setup.sql. Creates dbo.TradeColumnstore (about a minute of loading); 99-cleanup.sql
-- restores the database at the end of the module.
-- Turn on the actual plan in SSMS (Ctrl+M); the pages read are in the Messages tab.
USE LuminaQuant;
GO
SET STATISTICS IO, TIME ON;
GO
-- 1. The daily report, as the trading desk runs it: two months of trades, by day and venue.
EXEC dbo.GetDailyTradeVolume @From = '20250201', @To = '20250401';
GO
SET STATISTICS IO, TIME OFF;
GO
-- 2. A copy of the six columns of the covering index, stored in a clustered columnstore
--    index: the same 24 million rows, the same columns, another storage.
DROP TABLE IF EXISTS dbo.TradeColumnstore;
CREATE TABLE dbo.TradeColumnstore (
    TradeId    bigint        NOT NULL,
    ExecutedAt datetime2(3)  NOT NULL,
    VenueId    int           NOT NULL,
    Side       char(1)       NOT NULL,
    Quantity   decimal(18,8) NOT NULL,
    Price      decimal(18,8) NOT NULL,
    INDEX ccix_TradeColumnstore CLUSTERED COLUMNSTORE
);
GO
-- Loaded in one INSERT ... SELECT with TABLOCK: a parallel load.
INSERT INTO dbo.TradeColumnstore WITH (TABLOCK)
    (TradeId, ExecutedAt, VenueId, Side, Quantity, Price)
SELECT TradeId, ExecutedAt, VenueId, Side, Quantity, Price
FROM dbo.Trade;
GO
-- 3. The row groups after the load: their state, their size, and why they were cut short.
SELECT state_desc, trim_reason_desc, has_vertipaq_optimization, COUNT(*) AS RowGroups,
       SUM(total_rows) AS TotalRows, MIN(total_rows) AS MinRows, MAX(total_rows) AS MaxRows
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID(N'dbo.TradeColumnstore')
GROUP BY state_desc, trim_reason_desc, has_vertipaq_optimization
ORDER BY state_desc, trim_reason_desc;
GO
-- 4. The same six columns, in the rowstore index and in the columnstore copy.
SELECT i.name AS IndexName, i.type_desc, SUM(a.used_pages) * 8 / 1024 AS UsedMB
FROM sys.indexes AS i
JOIN sys.partitions AS p ON p.object_id = i.object_id AND p.index_id = i.index_id
JOIN sys.allocation_units AS a ON a.container_id = p.partition_id
WHERE (i.object_id = OBJECT_ID(N'dbo.Trade') AND i.name = N'IX_Trade_ExecutedAt')
   OR i.object_id = OBJECT_ID(N'dbo.TradeColumnstore')
GROUP BY i.name, i.type_desc;
GO
-- 5. The size of each column: the segments of one column, all row groups together.
SELECT c.name AS ColumnName, COUNT(*) AS Segments,
       SUM(s.on_disk_size) / 1024 AS SizeKB
FROM sys.column_store_segments AS s
JOIN sys.partitions AS p ON p.partition_id = s.partition_id
JOIN sys.columns AS c ON c.object_id = p.object_id AND c.column_id = s.column_id
WHERE p.object_id = OBJECT_ID(N'dbo.TradeColumnstore')
GROUP BY c.name
ORDER BY SizeKB DESC;
-- and the number of distinct values of each column.
SELECT COUNT(DISTINCT TradeId) AS TradeId, COUNT(DISTINCT ExecutedAt) AS ExecutedAt,
       COUNT(DISTINCT Price) AS Price, COUNT(DISTINCT Quantity) AS Quantity,
       COUNT(DISTINCT VenueId) AS VenueId, COUNT(DISTINCT Side) AS Side
FROM dbo.TradeColumnstore;
GO
SET STATISTICS IO, TIME ON;
GO
-- 6. What a scan reads: one column, then two, on each storage. The rowstore index reads
--    all its pages whatever the columns; the columnstore reads the segments of the columns
--    named in the query.
SELECT VenueId, COUNT_BIG(*) AS Trades
FROM dbo.Trade GROUP BY VenueId;
SELECT VenueId, COUNT_BIG(*) AS Trades
FROM dbo.TradeColumnstore GROUP BY VenueId;
SELECT VenueId, COUNT_BIG(*) AS Trades, SUM(Quantity) AS Quantity
FROM dbo.TradeColumnstore GROUP BY VenueId;
GO
-- 7. The query of the report on the copy: it names ExecutedAt, the largest column.
SELECT CAST(t.ExecutedAt AS date) AS TradeDate,
       v.Code                     AS Venue,
       COUNT_BIG(*)               AS Trades,
       CAST(SUM(t.Quantity * t.Price) AS decimal(19, 2)) AS Notional
FROM dbo.TradeColumnstore AS t
JOIN dbo.Venue AS v ON v.VenueId = t.VenueId
WHERE t.ExecutedAt >= '20250201'
  AND t.ExecutedAt <  '20250401'
GROUP BY CAST(t.ExecutedAt AS date), v.Code
ORDER BY TradeDate, Venue;
GO
SET STATISTICS IO, TIME OFF;
GO
