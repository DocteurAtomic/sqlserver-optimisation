-- Clip D6.1: the statistic recomputed by hand, and the report measured again.
-- Runs on the lab, in one session, after 01b-statistics-properties.sql. Recomputes one
-- statistic of this database; 00-setup.sql restores the database.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The plan of the report in the cache: one execution, 840,000 pages.
SELECT ps.execution_count, ps.last_logical_reads
FROM sys.dm_exec_procedure_stats AS ps
WHERE ps.database_id = DB_ID() AND ps.object_id = OBJECT_ID(N'Marketing.GetLetterResults');
GO
-- 2. The statistic of the index on CampaignId, recomputed with the default sample.
UPDATE STATISTICS Marketing.Delivery ix_Delivery_CampaignId;
GO
SELECT s.name AS StatisticName, p.last_updated, p.rows, p.rows_sampled, p.steps, p.modification_counter
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Marketing.Delivery') AND s.name = N'ix_Delivery_CampaignId';
SELECT TOP (2) step_number, range_high_key, equal_rows, range_rows
FROM sys.dm_db_stats_histogram(OBJECT_ID(N'Marketing.Delivery'),
                               INDEXPROPERTY(OBJECT_ID(N'Marketing.Delivery'), N'ix_Delivery_CampaignId', 'IndexId'))
ORDER BY step_number DESC;
GO
-- 3. The same call. No sp_recompile: the plan in the cache depends on a statistic that has
--    changed, and SQL Server recompiles the query before running it.
SET STATISTICS IO, TIME ON;
EXEC Marketing.GetLetterResults @CampaignId = 17391;
SET STATISTICS IO, TIME OFF;
GO
SELECT ps.execution_count, ps.last_logical_reads
FROM sys.dm_exec_procedure_stats AS ps
WHERE ps.database_id = DB_ID() AND ps.object_id = OBJECT_ID(N'Marketing.GetLetterResults');
GO
