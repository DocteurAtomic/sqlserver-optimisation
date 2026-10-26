-- Module V4, setup. Runs on the lab, in one session, before the first clip of the module.
-- It lasts about a minute.
-- 1. Restores LuminaQuant as delivered (master.dbo.reset_training only knows
--    PachadataTraining): the same RESTORE as setup/restore.sql, WITH REPLACE.
-- 2. Sets the degree of parallelism of the database to 2, as in PachadataTraining: with the
--    default (0), the engine of the lab sees 22 processors and runs the report on 22 threads
--    over 4 real ones, and the CPU times of the module mean nothing.
-- 3. The trading desk had widened the index on ExecutedAt so that it covers its daily report
--    (VenueId, Side, Quantity and Price included): the report reads this 1 GB index rather
--    than the 2.5 GB clustered index. About 30 seconds.
-- 4. The problem of the module: the daily report, dbo.GetDailyTradeVolume, carries the hint
--    OPTION (USE HINT ('DISALLOW_BATCH_MODE')). Someone added it after a support ticket on
--    batch mode and never took it back. At level 170 the optimizer would run this aggregate
--    in batch mode on the rowstore index by itself; the hint keeps it in row mode, and the
--    report burns half as much CPU again as it needs. Clip V4.4 tells it, and measures the
--    report once the hint is gone.
-- Demo scripts 01 to 04 create objects in LuminaQuant (a columnstore copy of the trades);
-- 99-cleanup.sql restores the database as delivered at the end of the module.
USE master;
GO
IF DB_ID(N'LuminaQuant') IS NOT NULL
    ALTER DATABASE LuminaQuant SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
RESTORE DATABASE LuminaQuant
    FROM DISK = N'/var/opt/mssql/backup/LuminaQuant.bak'
    WITH REPLACE,
         MOVE N'LuminaQuant' TO N'/var/opt/mssql/data/LuminaQuant.mdf',
         MOVE N'LuminaQuant_log' TO N'/var/opt/mssql/data/LuminaQuant_log.ldf';
GO
ALTER DATABASE LuminaQuant SET MULTI_USER;
ALTER DATABASE LuminaQuant SET COMPATIBILITY_LEVEL = 170;
GO
USE LuminaQuant;
GO
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 2;
GO
CREATE INDEX IX_Trade_ExecutedAt ON dbo.Trade (ExecutedAt)
    INCLUDE (VenueId, Side, Quantity, Price)
    WITH (DROP_EXISTING = ON);
GO
CREATE OR ALTER PROCEDURE dbo.GetDailyTradeVolume
    @From date,
    @To   date
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CAST(t.ExecutedAt AS date) AS TradeDate,
           v.Code                     AS Venue,
           COUNT_BIG(*)               AS Trades,
           CAST(SUM(t.Quantity * t.Price) AS decimal(19, 2)) AS Notional
    FROM dbo.Trade AS t
    JOIN dbo.Venue AS v ON v.VenueId = t.VenueId
    WHERE t.ExecutedAt >= @From
      AND t.ExecutedAt <  @To
    GROUP BY CAST(t.ExecutedAt AS date), v.Code
    ORDER BY TradeDate, Venue
    OPTION (USE HINT ('DISALLOW_BATCH_MODE'));
END;
GO
SELECT name, compatibility_level FROM sys.databases WHERE name = DB_NAME();
SELECT name, value FROM sys.database_scoped_configurations
WHERE name IN (N'MAXDOP', N'BATCH_MODE_ON_ROWSTORE');
SELECT i.name AS IndexName, i.type_desc, SUM(a.used_pages) AS UsedPages
FROM sys.indexes AS i
JOIN sys.partitions AS p ON p.object_id = i.object_id AND p.index_id = i.index_id
JOIN sys.allocation_units AS a ON a.container_id = p.partition_id
WHERE i.object_id = OBJECT_ID(N'dbo.Trade')
GROUP BY i.name, i.type_desc
ORDER BY i.name;
