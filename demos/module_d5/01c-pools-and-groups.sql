-- Clip D5.1: two resource pools, two workload groups, one classifier function. Runs on the
-- throwaway container, in one session. Changes the instance: 99-cleanup.sql removes it all.
-- ci: skip (it changes the resource governor of the instance)
-- No limit yet: the pools and groups are created with their default values, and the
-- classifier function sends each login to its group. The classification happens when a
-- session connects: stop charge.sh before, and start it again after this script.
USE master;
GO
CREATE RESOURCE POOL ReportPool;
CREATE RESOURCE POOL EntryPool;
CREATE WORKLOAD GROUP Reports USING ReportPool;
CREATE WORKLOAD GROUP Entry USING EntryPool;
GO
-- The classifier function: in master, WITH SCHEMABINDING, no parameter, a sysname that
-- names the group. It runs at every connection, so it reads no table: a CASE on the login.
-- Any other login (sa, SSMS, the Agent) goes to default.
CREATE FUNCTION dbo.ClassifySession()
RETURNS sysname
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE SUSER_SNAME()
               WHEN N'report_user' THEN N'Reports'
               WHEN N'entry_user' THEN N'Entry'
               ELSE N'default'
           END;
END;
GO
-- RECONFIGURE applies the configuration and turns the governor on.
ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = dbo.ClassifySession);
ALTER RESOURCE GOVERNOR RECONFIGURE;
GO
SELECT OBJECT_NAME(classifier_function_id) AS classifier_function, is_enabled
FROM sys.resource_governor_configuration;
SELECT p.name AS pool, p.min_cpu_percent, p.max_cpu_percent, p.cap_cpu_percent, p.max_memory_percent,
       g.name AS workload_group, g.request_max_memory_grant_percent, g.max_dop
FROM sys.resource_governor_resource_pools AS p
LEFT JOIN sys.resource_governor_workload_groups AS g ON g.pool_id = p.pool_id
ORDER BY p.pool_id, g.group_id;
