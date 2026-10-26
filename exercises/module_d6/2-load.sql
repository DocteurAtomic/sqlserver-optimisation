-- Exercise of module D6, the day of March 6. Runs on the lab, in one session, after
-- 1-start.sql. Lasts a few seconds.
-- 1. The first 30,000 trades of March 6, inserted one by one, as the application does,
--    committed every 1,000.
-- 2. The reports of the new risk application, each run a few times. GO n, a command of SSMS
--    and sqlcmd and not of Transact-SQL, repeats a batch n times.
USE ExoMaintenance;
GO
SET NOCOUNT ON;
DECLARE @id bigint = (SELECT MAX(TradeId) FROM dbo.Trade), @inserted int = 0;
BEGIN TRANSACTION;
WHILE @inserted < 30000
BEGIN
    SELECT TOP (1) @id = TradeId FROM LuminaQuant.dbo.Trade WHERE TradeId > @id ORDER BY TradeId;
    INSERT INTO dbo.Trade (TradeId, StrategyId, VenueId, InstrumentId, Side, Quantity, Price, ExecutedAt, ExternalId)
    SELECT TradeId, StrategyId, VenueId, InstrumentId, Side, Quantity, Price, ExecutedAt, ExternalId
    FROM LuminaQuant.dbo.Trade WHERE TradeId = @id;
    SET @inserted += 1;
    IF @inserted % 1000 = 0 BEGIN COMMIT; BEGIN TRANSACTION; END;
END;
COMMIT;
SELECT COUNT(*) AS March6Trades, MIN(ExecutedAt) AS FirstTrade, MAX(ExecutedAt) AS LastTrade
FROM dbo.Trade WHERE ExecutedAt >= '20250306';
GO
SELECT SUM(Quantity) AS Volume FROM dbo.Trade WHERE StrategyId = 9 AND VenueId = 3;
GO 4
SELECT SUM(Quantity * Price) AS Amount FROM dbo.Trade
WHERE StrategyId = 4 AND InstrumentId > 10 AND Side = 'B';
GO 3
SELECT COUNT(*) AS Trades FROM dbo.Trade WHERE VenueId = 3 AND Quantity > 1000;
GO 2
