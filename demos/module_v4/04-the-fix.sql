-- Clip V4.4, the end of the module: why the daily report runs in row mode on a database at
-- level 170, where the hint is, and the report measured before and after it goes. Runs on
-- the lab, in one session, after 03-delta-store-and-elimination.sql. Changes the procedure
-- dbo.GetDailyTradeVolume; 99-cleanup.sql restores the database at the end of the module.
-- Turn on the actual plan in SSMS (Ctrl+M).
USE LuminaQuant;
GO
-- The rebuilds of the previous clip pushed the index of the report out of memory: a first
-- call loads it, so that the two measures below compare warm runs.
EXEC dbo.GetDailyTradeVolume @From = '20250201', @To = '20250401';
GO
SET STATISTICS IO, TIME ON;
GO
-- 1. Before: the report as 00-setup.sql left it.
EXEC dbo.GetDailyTradeVolume @From = '20250201', @To = '20250401';
GO
SET STATISTICS IO, TIME OFF;
GO
-- 2. Batch mode on rowstore needs level 150 or later, and the database scoped
--    configuration BATCH_MODE_ON_ROWSTORE, ON by default.
SELECT name, compatibility_level FROM sys.databases WHERE name = DB_NAME();
SELECT name, value FROM sys.database_scoped_configurations
WHERE name = N'BATCH_MODE_ON_ROWSTORE';
GO
-- 3. A hint can still refuse it, query by query: in the code of a module...
SELECT OBJECT_SCHEMA_NAME(object_id) AS SchemaName, OBJECT_NAME(object_id) AS ModuleName
FROM sys.sql_modules
WHERE definition LIKE N'%DISALLOW_BATCH_MODE%';
-- ...or in a Query Store hint, set on the query without touching the code.
SELECT query_id, query_hint_text
FROM sys.query_store_query_hints;
GO
-- 4. The fix: the same procedure, without the hint.
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
    ORDER BY TradeDate, Venue;
END;
GO
SET STATISTICS IO, TIME ON;
GO
-- 5. After: the same call, compiled again since the procedure changed.
EXEC dbo.GetDailyTradeVolume @From = '20250201', @To = '20250401';
GO
SET STATISTICS IO, TIME OFF;
GO
