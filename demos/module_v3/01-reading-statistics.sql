-- Clip V3.1: reading a statistic. The marketing report measured, the statistics of
-- Contact.Contact listed, then the statistic of the index on LastName read in its three
-- parts. Runs on the lab, in one session, after 00-setup.sql. Reads only. Turn on the actual
-- plan in SSMS (Ctrl+M); the pages read are in the Messages tab.
USE PachadataTraining;
SET ARITHABORT ON;
GO
SET STATISTICS IO, TIME ON;
GO
-- 1. The targeting report, as the marketing team runs it: the women born from 1970 to 1992.
EXEC Marketing.GetCampaignTargets @Gender = 'F', @BornFrom = '19700101', @BornBefore = '19930101';
GO
SET STATISTICS IO, TIME OFF;
GO
-- 2. The statistics of Contact.Contact: one row per statistic, with its first column, the
--    date it was computed, the rows it read and the steps of its histogram.
SELECT s.name AS StatisticName,
       COL_NAME(sc.object_id, sc.column_id) AS FirstColumn,
       s.auto_created, s.user_created,
       p.last_updated, p.rows, p.rows_sampled, p.steps, p.modification_counter
FROM sys.stats AS s
JOIN sys.stats_columns AS sc
  ON sc.object_id = s.object_id AND sc.stats_id = s.stats_id AND sc.stats_column_id = 1
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Contact.Contact');
GO
-- 3. The statistic of the index nix_contact_lastname: header, density vector, histogram.
DBCC SHOW_STATISTICS (N'Contact.Contact', nix_contact_lastname);
GO
-- 4. The density of the first column is 1 / the number of distinct values.
SELECT COUNT(*) AS ContactRows,
       COUNT(DISTINCT LastName) AS DistinctNames,
       1.0 / COUNT(DISTINCT LastName) AS Density,
       COUNT(*) * 1.0 / COUNT(DISTINCT LastName) AS RowsPerName
FROM Contact.Contact;
GO
-- 5. Two steps of the histogram, read as a table: the most frequent name of the table is a
--    step of its own.
SELECT h.step_number, h.range_high_key, h.range_rows, h.equal_rows,
       h.distinct_range_rows, h.average_range_rows
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_histogram(s.object_id, s.stats_id) AS h
WHERE s.object_id = OBJECT_ID(N'Contact.Contact')
  AND s.name = N'nix_contact_lastname'
  AND h.range_high_key IN ('Martin', 'Simon');
GO
