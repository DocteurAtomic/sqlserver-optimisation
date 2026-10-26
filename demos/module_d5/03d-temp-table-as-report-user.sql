-- Clip D5.3: a report that fills a temporary table. Runs on the throwaway container,
-- CONNECTED AS report_user (password Lab#Reading2026, set in 00-setup.sql), after
-- 03c-tempdb-limit.sql. In SSMS: Query > Connection > Change Connection.
-- ci: skip (it needs the login report_user and the limit of 03c)
-- Three million rows of 104 bytes: more than 256 MB in tempdb. The statement fails with the
-- error 1138 when the group reaches its limit; the error ends the batch, and the
-- temporary table goes with the session.
USE PachadataTraining;
SET NOCOUNT ON;
GO
SELECT SUSER_SNAME() AS login_name;
SELECT CAST(value AS int) AS n, CAST('report' AS char(100)) AS pad
INTO #Export
FROM GENERATE_SERIES(1, 3000000);
SELECT COUNT(*) AS rows_in_export FROM #Export;
