-- Clip D6.1: what the statistics of Marketing.Delivery know, and what they do not know yet.
-- Runs on the lab, in one session, after 01a-the-report.sql. Reads only.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. One row per statistic: when it was computed, on how many rows, how many of them were
--    read, and how many modifications its leading column has had since. The two thresholds:
--    500 + 20 % of the rows until SQL Server 2014 (and below compatibility level 130), the
--    smaller of that and SQRT(1000 x rows) since SQL Server 2016.
SELECT s.name AS StatisticName, p.last_updated, p.rows, p.rows_sampled, p.steps,
       p.modification_counter,
       CAST(500 + 0.20 * p.rows AS bigint) AS OldThreshold,
       CAST(CASE WHEN SQRT(1000.0 * p.rows) < 500 + 0.20 * p.rows
                 THEN SQRT(1000.0 * p.rows) ELSE 500 + 0.20 * p.rows END AS bigint) AS Threshold
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Marketing.Delivery')
ORDER BY s.stats_id;
GO
-- 2. The last steps of the histogram of ix_Delivery_CampaignId: it stops at campaign 17390.
SELECT TOP (3) step_number, range_high_key, equal_rows, range_rows
FROM sys.dm_db_stats_histogram(OBJECT_ID(N'Marketing.Delivery'),
                               INDEXPROPERTY(OBJECT_ID(N'Marketing.Delivery'), N'ix_Delivery_CampaignId', 'IndexId'))
ORDER BY step_number DESC;
GO
-- 3. The density of CampaignId, which the estimate of a value beyond the histogram uses.
DBCC SHOW_STATISTICS (N'Marketing.Delivery', ix_Delivery_CampaignId) WITH DENSITY_VECTOR;
GO
-- 4. The estimate of the new campaign alone, with the current model and with the model of
--    SQL Server 7.0 to 2012. Read it in the actual plan (Ctrl+M), on the Index Seek.
SELECT COUNT(*) FROM Marketing.Delivery WHERE CampaignId = 17391 OPTION (RECOMPILE);
SELECT COUNT(*) FROM Marketing.Delivery WHERE CampaignId = 17391
OPTION (RECOMPILE, USE HINT ('FORCE_LEGACY_CARDINALITY_ESTIMATION'));
GO
