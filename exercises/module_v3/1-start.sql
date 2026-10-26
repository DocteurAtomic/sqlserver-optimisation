-- Exercise of module V3, start. Runs on the lab, in one session. It lasts a few seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. Turns AUTO_CREATE_STATISTICS off for the database, and drops the statistics the
--    optimizer had created on Contact.ProspectUS_N: the million prospects of that heap have
--    no statistic left, and no index.
-- 3. Gives the queries of the three parts.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
ALTER DATABASE CURRENT SET AUTO_CREATE_STATISTICS OFF;
GO
DECLARE @sql nvarchar(max) = N'';
SELECT @sql += N'DROP STATISTICS Contact.ProspectUS_N.' + QUOTENAME(name) + N';'
FROM sys.stats
WHERE object_id = OBJECT_ID(N'Contact.ProspectUS_N') AND auto_created = 1;
EXEC sys.sp_executesql @sql;
GO
SELECT COUNT(*) AS StatisticsLeft
FROM sys.stats
WHERE object_id = OBJECT_ID(N'Contact.ProspectUS_N');
GO
-- Part 1. Four queries on City, without statistic. Run each with the actual plan (Ctrl+M),
-- and note, on the Table Scan, the estimated and the actual number of rows. The table holds
-- 1,000,000 rows: find the rule behind each estimate.
/*
SELECT COUNT(*) FROM Contact.ProspectUS_N WHERE City = N'Arlington';
SELECT COUNT(*) FROM Contact.ProspectUS_N WHERE City LIKE N'Los%';
SELECT COUNT(*) FROM Contact.ProspectUS_N WHERE City > N'S';
SELECT LastName, FirstName, Email
FROM Contact.ProspectUS_N
WHERE City IN (N'Arlington', N'Columbus', N'Los Angeles')
ORDER BY Email;
*/
-- Part 2. Create a statistic on City, read in full, then run the first query again as it
-- is, and once more with OPTION (RECOMPILE). Then the fourth query. What changed, and when?
/*
CREATE STATISTICS st_prospectusn_city ON Contact.ProspectUS_N (City) WITH FULLSCAN;
*/
-- Part 3. Read the statistic with DBCC SHOW_STATISTICS. Before running them, say what the
-- optimizer will estimate for these two queries, and from which part of the statistic.
/*
SELECT COUNT(*) FROM Contact.ProspectUS_N WHERE City = N'Columbus' OPTION (RECOMPILE);

DECLARE @City nvarchar(255) = N'Columbus';
SELECT COUNT(*) FROM Contact.ProspectUS_N WHERE City = @City;
*/
