-- Exercise of module V5, start. Runs on the lab, in one session. It lasts about ten seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170 (the parameter
--    sensitive plan optimization is on, its default).
-- 2. Creates the index nix_activity_moduleid on Elearning.Activity (ModuleId), 7.8 million
--    rows, about six seconds.
-- 3. Creates Elearning.GetModuleActivity, the activity of one module of the e-learning
--    platform, per event type and per device, used by the dashboard of the trainers.
-- The questions are in README.md; the queries of each part are given below, in comments.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
CREATE INDEX nix_activity_moduleid ON Elearning.Activity (ModuleId);
GO
CREATE OR ALTER PROCEDURE Elearning.GetModuleActivity @ModuleId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.EventTypeCode, a.Device, COUNT(*) AS Events, SUM(a.DurationSeconds) AS Seconds
    FROM Elearning.Activity AS a
    WHERE a.ModuleId = @ModuleId
    GROUP BY a.EventTypeCode, a.Device;
END;
GO
-- The modules: the busiest and the quietest.
SELECT TOP (3) ModuleId, COUNT(*) AS Events
FROM Elearning.Activity WHERE ModuleId IS NOT NULL
GROUP BY ModuleId ORDER BY Events DESC;
SELECT TOP (3) ModuleId, COUNT(*) AS Events
FROM Elearning.Activity
GROUP BY ModuleId ORDER BY Events ASC;
GO
/*
Part 1. With SET STATISTICS IO, TIME ON and the actual plan (Ctrl+M):
EXEC sys.sp_recompile N'Elearning.GetModuleActivity';
EXEC Elearning.GetModuleActivity @ModuleId = 992;
EXEC Elearning.GetModuleActivity @ModuleId = 808;
EXEC sys.sp_recompile N'Elearning.GetModuleActivity';
EXEC Elearning.GetModuleActivity @ModuleId = 808;
EXEC Elearning.GetModuleActivity @ModuleId = 992;

Part 2. After the calls of part 1, the cache of the procedure:
SELECT cp.objtype, cp.usecounts, LEFT(st.text, 60) AS StartOfText
FROM sys.dm_exec_cached_plans AS cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) AS st
WHERE st.dbid = DB_ID() AND st.text LIKE N'%FROM Elearning.Activity AS a%'
  AND st.text NOT LIKE N'%dm_exec_cached_plans%';

Part 3. Your remedy, measured on the same calls as part 1.
*/
