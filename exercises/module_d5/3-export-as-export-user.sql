-- Module D5 exercise: the export, as the export tool runs it. Runs on your lab, CONNECTED AS
-- export_user (password Lab#Export2026, set in 1-start.sql), after part 2.
-- ci: skip (it needs the login export_user and the configuration of the exercise)
-- In SSMS: Query > Connection > Change Connection, SQL Server authentication.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- The export: the same query as in part 3, so that part 4 finds both plans by their text.
SELECT TOP (100) ContactId, ModuleId, COUNT(*) AS Events,
       SUM(CAST(DurationSeconds AS bigint)) AS Seconds
FROM Elearning.Activity
GROUP BY ContactId, ModuleId
ORDER BY Seconds DESC;
GO
-- The detail file of the export, built in a temporary table: every event of the log.
SELECT ActivityId, EventTime, ContactId, ModuleId, EventTypeCode, DurationSeconds, Device
INTO #ExportDetail
FROM Elearning.Activity;
SELECT COUNT(*) AS detail_rows FROM #ExportDetail;
GO
