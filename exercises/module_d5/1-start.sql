-- Module D5 exercise: start. Runs on your lab, in one session, after the 99-cleanup.sql of
-- the module (resource governor off, no classifier function).
-- ci: skip (the exercise creates a login and changes the resource governor of the instance)
-- Restores PachadataTraining as delivered, creates the login of the e-learning export,
-- export_user, and its user, reads the state of the governor, then gives the skeleton of
-- the exercise, which does not run until you remove the line SET NOEXEC ON. 5-cleanup.sql
-- puts the instance back in the state read here.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
-- The state to note: 5-cleanup.sql comes back to it. One classifier function at most for
-- the whole instance: if one is already declared, play the 99-cleanup.sql of the module.
SELECT OBJECT_NAME(classifier_function_id) AS classifier_function, is_enabled
FROM sys.resource_governor_configuration;
SELECT name AS pool FROM sys.resource_governor_resource_pools;
SELECT name AS workload_group FROM sys.resource_governor_workload_groups;
SELECT COUNT(*) AS visible_schedulers FROM sys.dm_os_schedulers WHERE status = N'VISIBLE ONLINE';
GO
-- The login of the export tool of the e-learning team. It reads the Elearning schema.
IF SUSER_ID(N'export_user') IS NOT NULL DROP LOGIN export_user;
CREATE LOGIN export_user WITH PASSWORD = N'Lab#Export2026', DEFAULT_DATABASE = PachadataTraining;
GO
USE PachadataTraining;
CREATE USER export_user FOR LOGIN export_user;
GRANT SELECT ON SCHEMA::Elearning TO export_user;
GO

SET NOEXEC ON;
GO
USE master;
GO
-- Part 1. The objects.
-- Your turn: the pool ExportPool, which may use one processor of your lab and no more,
-- whatever the load (compute the percentage from the schedulers read above), and at most
-- 20 % of the memory of the instance.
-- Your turn: the workload group Export in this pool: serial queries, a grant of at most 5 %
-- of the memory of the pool per query, and 64 MB of tempdb for the whole group.

-- Part 2. The classification.
-- Your turn: the classifier function dbo.ClassifyExport, which sends export_user to Export
-- and every other session to default; declare it to the governor and apply the
-- configuration.

-- Part 3. In this window (sa, group default), run the export once. Then run
-- 3-export-as-export-user.sql in a new window connected as export_user.
USE PachadataTraining;
SELECT TOP (100) ContactId, ModuleId, COUNT(*) AS Events,
       SUM(CAST(DurationSeconds AS bigint)) AS Seconds
FROM Elearning.Activity
GROUP BY ContactId, ModuleId
ORDER BY Seconds DESC;

-- Part 4, back as sa.
-- Your turn: for each cached plan of the export, the last degree of parallelism, the last
-- grant, the memory used and the pages spilled, the processor time (sys.dm_exec_query_stats).
-- Your turn: what each group used of tempdb, and its violations of the limit
-- (sys.dm_resource_governor_workload_groups).
GO
SET NOEXEC OFF;
GO
