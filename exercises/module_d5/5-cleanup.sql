-- Module D5 exercise: cleanup. Runs on your lab, as sa, after 4-solution-measures.sql, the
-- window of export_user closed (an open session would prevent DROP LOGIN).
-- ci: skip (it changes the resource governor of the instance and drops a login)
-- Puts the governor back in the state read by 1-start.sql: off, no classifier function.
USE master;
SET NOCOUNT ON;
GO
DECLARE @k nvarchar(max) = N'';
SELECT @k += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; '
FROM sys.dm_exec_sessions
WHERE login_name = N'export_user';
EXEC (@k);
GO
ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL);
ALTER RESOURCE GOVERNOR DISABLE;
IF EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = N'Export') DROP WORKLOAD GROUP Export;
IF EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = N'ExportPool') DROP RESOURCE POOL ExportPool;
IF OBJECT_ID(N'dbo.ClassifyExport') IS NOT NULL DROP FUNCTION dbo.ClassifyExport;
ALTER RESOURCE GOVERNOR RECONFIGURE;
ALTER RESOURCE GOVERNOR DISABLE;
GO
IF SUSER_ID(N'export_user') IS NOT NULL DROP LOGIN export_user;
GO
SELECT OBJECT_NAME(classifier_function_id) AS classifier_function, is_enabled
FROM sys.resource_governor_configuration;
SELECT name AS pool FROM sys.resource_governor_resource_pools;
SELECT name AS workload_group FROM sys.resource_governor_workload_groups;
