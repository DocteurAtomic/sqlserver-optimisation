-- Clip V3.4, the end of the module: AUTO_CREATE_STATISTICS back on, and the report measured
-- before and after. Runs on the lab, in one session, after 04a-tipping-point.sql. Changes an
-- option of this database and lets the optimizer create its statistics; 00-setup.sql of the
-- next module restores the database.
USE PachadataTraining;
SET ARITHABORT ON;
GO
SET STATISTICS IO, TIME ON;
GO
-- Before: the report with the database as 00-setup.sql left it.
EXEC Marketing.GetCampaignTargets @Gender = 'F', @BornFrom = '19700101', @BornBefore = '19930101';
GO
SET STATISTICS IO, TIME OFF;
GO
-- The plan of the report is in the cache.
SELECT COUNT(*) AS CachedPlans
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Marketing.GetCampaignTargets');
GO
-- The fix: the optimizer creates again the statistics its queries need.
ALTER DATABASE CURRENT SET AUTO_CREATE_STATISTICS ON;
GO
-- Changing a database option invalidates the plans of the database.
SELECT COUNT(*) AS CachedPlans
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Marketing.GetCampaignTargets');
GO
SET STATISTICS IO, TIME ON;
GO
-- After: the same call. It is compiled again, and the compilation creates the statistics.
EXEC Marketing.GetCampaignTargets @Gender = 'F', @BornFrom = '19700101', @BornBefore = '19930101';
GO
SET STATISTICS IO, TIME OFF;
GO
-- The statistics the optimizer created during the compilation.
SELECT s.name AS StatisticName,
       COL_NAME(sc.object_id, sc.column_id) AS FirstColumn,
       s.auto_created, p.rows, p.rows_sampled, p.steps
FROM sys.stats AS s
JOIN sys.stats_columns AS sc
  ON sc.object_id = s.object_id AND sc.stats_id = s.stats_id AND sc.stats_column_id = 1
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Contact.Contact');
GO
