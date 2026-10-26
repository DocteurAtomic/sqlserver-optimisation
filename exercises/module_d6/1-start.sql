-- Exercise of module D6, start. Runs on the lab, in one session. Lasts about ten seconds.
-- 1. Creates the database ExoMaintenance, in simple recovery, with one table, dbo.Trade:
--    the 1,413,356 trades of March 5, 2025, copied from LuminaQuant (read only).
-- 2. Indexes the table as the trading application left it: the clustered primary key on
--    TradeId, an index on the execution time, an index on the price, filled to 100 %, and
--    an index on ExternalId, the identifier of a former broker interface.
-- 3. Shows the statistics and the size of the indexes. 2-load.sql follows.
USE master;
GO
IF DB_ID(N'ExoMaintenance') IS NOT NULL
BEGIN
    ALTER DATABASE ExoMaintenance SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ExoMaintenance;
END;
GO
CREATE DATABASE ExoMaintenance;
GO
ALTER DATABASE ExoMaintenance SET RECOVERY SIMPLE;
GO
USE ExoMaintenance;
GO
CREATE TABLE dbo.Trade (
    TradeId      bigint        NOT NULL CONSTRAINT PK_Trade PRIMARY KEY CLUSTERED,
    StrategyId   int           NOT NULL,
    VenueId      int           NOT NULL,
    InstrumentId int           NOT NULL,
    Side         char(1)       NOT NULL,
    Quantity     decimal(18,8) NOT NULL,
    Price        decimal(18,8) NOT NULL,
    ExecutedAt   datetime2(3)  NOT NULL,
    ExternalId   nvarchar(40)  NULL
);
INSERT INTO dbo.Trade WITH (TABLOCK)
       (TradeId, StrategyId, VenueId, InstrumentId, Side, Quantity, Price, ExecutedAt, ExternalId)
SELECT TradeId, StrategyId, VenueId, InstrumentId, Side, Quantity, Price, ExecutedAt, ExternalId
FROM LuminaQuant.dbo.Trade
WHERE ExecutedAt >= '20250305' AND ExecutedAt < '20250306';
GO
-- The statistic of each index is computed on every row when the index is created.
CREATE INDEX IX_Trade_ExecutedAt ON dbo.Trade (ExecutedAt);
CREATE INDEX IX_Trade_Price ON dbo.Trade (Price) WITH (FILLFACTOR = 100);
CREATE INDEX IX_Trade_ExternalId ON dbo.Trade (ExternalId);
GO
SET NOCOUNT ON;
SELECT s.name AS StatisticName, p.rows, p.rows_sampled, p.steps, p.modification_counter
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'dbo.Trade');
SELECT i.name AS IndexName, SUM(ps.used_page_count) AS UsedPages
FROM sys.indexes AS i
JOIN sys.dm_db_partition_stats AS ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'dbo.Trade')
GROUP BY i.index_id, i.name
ORDER BY i.index_id;
GO
