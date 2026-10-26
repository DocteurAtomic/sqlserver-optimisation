-- Clip V3.2: the estimation. How the estimator uses the histogram and the density, what it
-- guesses with no statistic, and the two cardinality estimation models. Runs on the lab, in
-- one session, after 01-reading-statistics.sql. Reads only. Turn on the actual plan in SSMS
-- (Ctrl+M) and hover the first operator: Estimated Number of Rows against Actual Number of
-- Rows. OPTION (RECOMPILE) compiles each query for its literal values, so that no plan of an
-- earlier run is reused.
USE PachadataTraining;
GO
-- 1. A step boundary, then a value inside a step.
SELECT ContactId, LastName, FirstName FROM Contact.Contact
WHERE LastName = 'Simon' OPTION (RECOMPILE);

SELECT ContactId, LastName, FirstName FROM Contact.Contact
WHERE LastName = 'Zimmermann' OPTION (RECOMPILE);
GO
-- The step that holds Zimmermann: the first step whose upper bound is at or above it.
SELECT TOP (1) h.step_number, h.range_high_key, h.range_rows, h.equal_rows,
       h.distinct_range_rows, h.average_range_rows
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_histogram(s.object_id, s.stats_id) AS h
WHERE s.object_id = OBJECT_ID(N'Contact.Contact')
  AND s.name = N'nix_contact_lastname'
  AND h.range_high_key >= 'Zimmermann'
ORDER BY h.step_number;
GO
-- 2. A local variable: its value is unknown when the batch is compiled. The estimator falls
--    back on the density: rows x All density.
DECLARE @LastName varchar(50) = 'Simon';
SELECT ContactId, LastName, FirstName FROM Contact.Contact
WHERE LastName = @LastName;
GO
-- The same density explains the 244.6 deliveries estimated in module 3 for campaign 14 in a
-- variable: 4,018,304 rows x All density of CampaignId.
DBCC SHOW_STATISTICS (N'Marketing.Delivery', ix_Delivery_CampaignId) WITH DENSITY_VECTOR;
GO
-- 3. No statistic: the two columns of the report, one predicate at a time, then together.
SELECT COUNT(*) AS Women FROM Contact.Contact
WHERE Gender = 'F' OPTION (RECOMPILE);

SELECT COUNT(*) AS BornFrom1970 FROM Contact.Contact
WHERE BirthDate >= '19700101' OPTION (RECOMPILE);

SELECT COUNT(*) AS Born1970To1992 FROM Contact.Contact
WHERE BirthDate >= '19700101' AND BirthDate < '19930101' OPTION (RECOMPILE);

SELECT COUNT(*) AS Targets FROM Contact.Contact
WHERE Gender = 'F' AND BirthDate >= '19700101' AND BirthDate < '19930101'
OPTION (RECOMPILE);
GO
-- 4. The same query under the legacy model (70), then under the model of level 160,
--    SQL Server 2022.
SELECT COUNT(*) AS Targets FROM Contact.Contact
WHERE Gender = 'F' AND BirthDate >= '19700101' AND BirthDate < '19930101'
OPTION (RECOMPILE, USE HINT ('FORCE_LEGACY_CARDINALITY_ESTIMATION'));

SELECT COUNT(*) AS Targets FROM Contact.Contact
WHERE Gender = 'F' AND BirthDate >= '19700101' AND BirthDate < '19930101'
OPTION (RECOMPILE, USE HINT ('QUERY_OPTIMIZER_COMPATIBILITY_LEVEL_160'));
GO
