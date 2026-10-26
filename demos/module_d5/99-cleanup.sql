-- Module D5, cleanup: puts the instance back as the lab was delivered. Runs in one session,
-- after charge.sh has stopped.
-- ci: skip (it changes the resource governor of the instance and drops two logins)
-- Values read on a new container of the lab image (2025-CU7): resource governor off, no
-- classifier function, the pools and groups internal and default only. The function must
-- leave the configuration before it can be dropped; the groups go before their pools.
-- RECONFIGURE loads the configuration without them and turns the governor on, so DISABLE
-- comes last. The users of the two logins live in PachadataTraining: the next module's
-- 00-setup.sql restores the database without them.
USE master;
SET NOCOUNT ON;
GO
DECLARE @k nvarchar(max) = N'';
SELECT @k += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; '
FROM sys.dm_exec_sessions
WHERE login_name IN (N'report_user', N'entry_user');
EXEC (@k);
GO
ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL);
ALTER RESOURCE GOVERNOR DISABLE;
IF EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = N'Reports') DROP WORKLOAD GROUP Reports;
IF EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = N'Entry') DROP WORKLOAD GROUP Entry;
IF EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = N'ReportPool') DROP RESOURCE POOL ReportPool;
IF EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = N'EntryPool') DROP RESOURCE POOL EntryPool;
IF OBJECT_ID(N'dbo.ClassifySession') IS NOT NULL DROP FUNCTION dbo.ClassifySession;
ALTER RESOURCE GOVERNOR RECONFIGURE;
ALTER RESOURCE GOVERNOR DISABLE;
GO
IF SUSER_ID(N'report_user') IS NOT NULL DROP LOGIN report_user;
IF SUSER_ID(N'entry_user') IS NOT NULL DROP LOGIN entry_user;
GO
SELECT OBJECT_NAME(classifier_function_id) AS classifier_function, is_enabled
FROM sys.resource_governor_configuration;
SELECT name AS pool FROM sys.resource_governor_resource_pools;
SELECT name AS workload_group FROM sys.resource_governor_workload_groups;
SELECT COUNT(*) AS module_logins_left
FROM sys.server_principals
WHERE name IN (N'report_user', N'entry_user');
