-- Clip V3.3: correcting the estimate. Statistics created by hand, the plan in the cache that
-- does not see them, a filtered statistic, and the size of the sample. Runs on the lab, in
-- one session, after 02-estimation.sql. Creates statistics on Contact.Contact and
-- Marketing.Delivery, and drops them at the end: the module ends, in 04b-the-fix.sql, from
-- the state 00-setup.sql left. Turn on the actual plan in SSMS (Ctrl+M).
USE PachadataTraining;
SET ARITHABORT ON;
GO
-- 1. A statistic on BirthDate, read in full, then one on Gender. The count of the report's
--    contacts is compiled again after each.
CREATE STATISTICS st_contact_birthdate ON Contact.Contact (BirthDate) WITH FULLSCAN;
GO
SELECT COUNT(*) AS Targets FROM Contact.Contact
WHERE Gender = 'F' AND BirthDate >= '19700101' AND BirthDate < '19930101'
OPTION (RECOMPILE);
GO
CREATE STATISTICS st_contact_gender ON Contact.Contact (Gender) WITH FULLSCAN;
GO
SELECT COUNT(*) AS Targets FROM Contact.Contact
WHERE Gender = 'F' AND BirthDate >= '19700101' AND BirthDate < '19930101'
OPTION (RECOMPILE);
GO
-- 2. The report. Its plan was compiled in clip V3.1, without statistics, and stays in the
--    cache: creating a statistic does not recompile it.
SET STATISTICS IO ON;
GO
EXEC Marketing.GetCampaignTargets @Gender = 'F', @BornFrom = '19700101', @BornBefore = '19930101';
GO
EXEC sys.sp_recompile N'Marketing.GetCampaignTargets';
GO
EXEC Marketing.GetCampaignTargets @Gender = 'F', @BornFrom = '19700101', @BornBefore = '19930101';
GO
SET STATISTICS IO OFF;
GO
-- 3. A filtered statistic: the histogram of BirthDate for the women only. The estimator no
--    longer combines two selectivities.
CREATE STATISTICS st_contact_birthdate_women ON Contact.Contact (BirthDate)
WHERE Gender = 'F' WITH FULLSCAN;
GO
SELECT COUNT(*) AS Targets FROM Contact.Contact
WHERE Gender = 'F' AND BirthDate >= '19700101' AND BirthDate < '19930101'
OPTION (RECOMPILE);
GO
-- 4. The sample. The statistic the optimizer created on Marketing.Delivery.SendDate, then
--    two statistics asked with a tiny sample, then one read in full.
SELECT s.name AS StatisticName, p.rows, p.rows_sampled,
       CAST(100.0 * p.rows_sampled / p.rows AS decimal(5, 1)) AS SamplePercent, p.steps
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Marketing.Delivery')
  AND s.auto_created = 1
  AND COL_NAME(s.object_id, (SELECT sc.column_id FROM sys.stats_columns AS sc
                             WHERE sc.object_id = s.object_id AND sc.stats_id = s.stats_id
                               AND sc.stats_column_id = 1)) = N'SendDate';
GO
CREATE STATISTICS st_delivery_senddate_10rows ON Marketing.Delivery (SendDate) WITH SAMPLE 10 ROWS;
CREATE STATISTICS st_delivery_senddate_1pct ON Marketing.Delivery (SendDate) WITH SAMPLE 1 PERCENT;
CREATE STATISTICS st_delivery_senddate_full ON Marketing.Delivery (SendDate) WITH FULLSCAN;
GO
SELECT s.name AS StatisticName, p.rows, p.rows_sampled,
       CAST(100.0 * p.rows_sampled / p.rows AS decimal(5, 1)) AS SamplePercent, p.steps
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Marketing.Delivery')
  AND s.name LIKE N'st[_]delivery[_]senddate[_]%';
GO
-- 5. Back to the state of the setup for the end of the module: the statistics created here
--    are dropped, and the report will be compiled again without them.
DROP STATISTICS Marketing.Delivery.st_delivery_senddate_10rows,
                Marketing.Delivery.st_delivery_senddate_1pct,
                Marketing.Delivery.st_delivery_senddate_full,
                Contact.Contact.st_contact_birthdate,
                Contact.Contact.st_contact_gender,
                Contact.Contact.st_contact_birthdate_women;
GO
EXEC sys.sp_recompile N'Marketing.GetCampaignTargets';
GO
