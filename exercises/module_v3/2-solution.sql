-- Exercise of module V3, solution. Runs on the lab, in one session, after 1-start.sql.
-- Part 1: the four guesses of the estimator without statistic. Part 2: the statistic created,
-- the plan of the cache that ignores it, and the estimates once compiled again. Part 3: the
-- histogram and the density read before running. Drops the statistic at the end and turns
-- AUTO_CREATE_STATISTICS back on.
-- The estimates quoted were measured on the lab (SORTIES.md of the module); read them on the
-- Table Scan of the actual plan (Ctrl+M).
USE PachadataTraining;
GO
-- Part 1. Contact.ProspectUS_N: 1,000,000 rows, 24,524 pages, no index, no statistic.
-- 1. Equality: 1,000 estimated, the square root of the rows; 20,342 actual. The literal is
--    replaced by @1 (simple parameterization): the plan is trivial, and kept in the cache.
SELECT COUNT(*) AS Arlington FROM Contact.ProspectUS_N WHERE City = N'Arlington';
-- 2. LIKE with a prefix: 90,000 estimated, 9 percent of the rows; 10,332 actual.
SELECT COUNT(*) AS LosSomething FROM Contact.ProspectUS_N WHERE City LIKE N'Los%';
-- 3. Inequality: 300,000 estimated, 30 percent; 221,348 actual.
SELECT COUNT(*) AS AfterS FROM Contact.ProspectUS_N WHERE City > N'S';
-- 4. Three equalities joined by OR: 1,749 estimated, about 1,000 x (1 + 1/2 + 1/4), the
--    exponential backoff of the model applied to three guesses; 51,023 actual. The Sort
--    gets a memory grant sized for 1,749 rows (2,976 KB) and spills to tempdb: warning
--    SpillToTempDb on the Sort.
SELECT LastName, FirstName, Email
FROM Contact.ProspectUS_N
WHERE City IN (N'Arlington', N'Columbus', N'Los Angeles')
ORDER BY Email;
GO
-- These guesses are constants: they do not depend on the data, and do not move when the
-- data changes.

-- Part 2. The statistic, read in full.
CREATE STATISTICS st_prospectusn_city ON Contact.ProspectUS_N (City) WITH FULLSCAN;
GO
-- The first query, as it is: still 1,000 estimated. Its trivial plan, parameterized as
-- [City] = @1, comes from the cache, and creating a statistic did not recompile it.
SELECT COUNT(*) AS Arlington FROM Contact.ProspectUS_N WHERE City = N'Arlington';
-- Compiled again, the estimates come from the histogram: 20,342 (exact), 10,377.8 for
-- the LIKE (the string summary of the statistic), 221,348 for the inequality.
SELECT COUNT(*) AS Arlington FROM Contact.ProspectUS_N WHERE City = N'Arlington' OPTION (RECOMPILE);
SELECT COUNT(*) AS LosSomething FROM Contact.ProspectUS_N WHERE City LIKE N'Los%' OPTION (RECOMPILE);
SELECT COUNT(*) AS AfterS FROM Contact.ProspectUS_N WHERE City > N'S' OPTION (RECOMPILE);
-- The three cities: 51,023 estimated and actual, 20,288 KB granted, no spill.
SELECT LastName, FirstName, Email
FROM Contact.ProspectUS_N
WHERE City IN (N'Arlington', N'Columbus', N'Los Angeles')
ORDER BY Email
OPTION (RECOMPILE);
GO
-- Part 3. The statistic: 97 steps, one per city plus NULL (10,097 prospects without city).
DBCC SHOW_STATISTICS (N'Contact.ProspectUS_N', st_prospectusn_city);
GO
-- Columbus is a step of the histogram: EQ_ROWS 20,349, the estimate is exact.
SELECT COUNT(*) AS Columbus FROM Contact.ProspectUS_N WHERE City = N'Columbus' OPTION (RECOMPILE);
GO
-- In a variable, the value is unknown at compilation: the estimator takes the density, All
-- density 1/97 (NULL counts as a value) times the rows, about 10,300 (10,311.5 in the plan),
-- for 20,349 actual. Columbus is one of the two largest cities: the average halves it.
DECLARE @City nvarchar(255) = N'Columbus';
SELECT COUNT(*) AS Columbus FROM Contact.ProspectUS_N WHERE City = @City;
GO
-- Cleanup: the statistic created here is dropped, the database option restored.
DROP STATISTICS Contact.ProspectUS_N.st_prospectusn_city;
GO
ALTER DATABASE CURRENT SET AUTO_CREATE_STATISTICS ON;
GO
