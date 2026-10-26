-- Clip D6.4, the end of the module: the problem revealed, the option back on, and the report
-- of the December letter measured again. Runs on the lab, in one session, after
-- 04a-december-letter.sql. Changes an option of this database; 00-setup.sql of the next
-- module restores the database.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The three places where an automatic update can be stopped: the database option, its
--    asynchronous variant, and NORECOMPUTE on a statistic.
SELECT name, is_auto_update_stats_on, is_auto_update_stats_async_on
FROM sys.databases WHERE name = DB_NAME();
SELECT COUNT(*) AS NoRecomputeStatistics FROM sys.stats WHERE no_recompute = 1;
GO
-- 2. The fix. Changing a database option also removes the plans of the database from the
--    cache.
ALTER DATABASE CURRENT SET AUTO_UPDATE_STATISTICS ON;
GO
-- 3. The same call: before compiling it, the optimizer finds the statistic out of date and
--    recomputes it, on a sample.
SET STATISTICS IO, TIME ON;
EXEC Marketing.GetLetterResults @CampaignId = 17392;
SET STATISTICS IO, TIME OFF;
GO
SELECT s.name AS StatisticName, p.last_updated, p.rows, p.rows_sampled, p.modification_counter
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Marketing.Delivery')
ORDER BY s.stats_id;
GO
