-- Clip V4.2: batch mode. The same aggregate on the rowstore index and on the columnstore
-- copy, each in row mode (hint DISALLOW_BATCH_MODE) and in batch mode, then the query of the
-- report on the copy. Runs on the lab, in one session, after 01-column-storage.sql.
-- Reads only; about a minute. Turn on the actual plan in SSMS (Ctrl+M): the execution mode
-- of each operator is in its properties (Actual Execution Mode), the pages read and the CPU
-- time in the Messages tab.
USE LuminaQuant;
GO
SET STATISTICS IO, TIME ON;
GO
-- 1. Rowstore index, row mode.
SELECT VenueId, COUNT_BIG(*) AS Trades, SUM(Quantity) AS Quantity
FROM dbo.Trade
GROUP BY VenueId
OPTION (USE HINT ('DISALLOW_BATCH_MODE'));
-- 2. Rowstore index, batch mode: the optimizer chooses it by itself at level 150 and later.
SELECT VenueId, COUNT_BIG(*) AS Trades, SUM(Quantity) AS Quantity
FROM dbo.Trade
GROUP BY VenueId;
-- 3. Columnstore, row mode.
SELECT VenueId, COUNT_BIG(*) AS Trades, SUM(Quantity) AS Quantity
FROM dbo.TradeColumnstore
GROUP BY VenueId
OPTION (USE HINT ('DISALLOW_BATCH_MODE'));
-- 4. Columnstore, batch mode.
SELECT VenueId, COUNT_BIG(*) AS Trades, SUM(Quantity) AS Quantity
FROM dbo.TradeColumnstore
GROUP BY VenueId;
GO
-- 5. The query of the report on the copy, in batch mode: it groups on an expression,
--    CAST(ExecutedAt AS date), and sums a product computed row by row.
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
