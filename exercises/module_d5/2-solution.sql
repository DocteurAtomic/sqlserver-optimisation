-- Module D5 exercise: solution of parts 1 and 2. Runs on your lab, as sa, after 1-start.sql.
-- ci: skip (it changes the resource governor of the instance)
-- Then run part 3 (the export as sa, in this window, and 3-export-as-export-user.sql in a
-- window connected as export_user), then 4-solution-measures.sql, then 5-cleanup.sql.
USE master;
GO
-- Part 1. One processor out of the schedulers SQL Server sees: CAP_CPU_PERCENT = 100 /
-- schedulers, rounded up (5 with 22 schedulers: 1.1 processors). The percentages of the
-- governor are shares of the schedulers, not of the processors of the container.
-- MAX_CPU_PERCENT would not do: it only applies when another pool wants the processor on
-- the same scheduler. MAX_MEMORY_PERCENT bounds the whole pool, grants and cache of plans.
DECLARE @schedulers int = (SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = N'VISIBLE ONLINE');
DECLARE @cap int = CEILING(100.0 / @schedulers);
DECLARE @sql nvarchar(300) = N'CREATE RESOURCE POOL ExportPool WITH (CAP_CPU_PERCENT = '
                           + CAST(@cap AS nvarchar(3)) + N', MAX_MEMORY_PERCENT = 20);';
EXEC (@sql);
GO
-- The group: MAX_DOP = 1 overrides the MAXDOP of the base (2) and of the instance;
-- REQUEST_MAX_MEMORY_GRANT_PERCENT is a share of the memory of the pool, not of the
-- instance; GROUP_MAX_TEMPDB_DATA_MB (SQL Server 2025) counts the data pages of tempdb of
-- all the sessions of the group together.
CREATE WORKLOAD GROUP Export
WITH (MAX_DOP = 1, REQUEST_MAX_MEMORY_GRANT_PERCENT = 5, GROUP_MAX_TEMPDB_DATA_MB = 64)
USING ExportPool;
GO
-- Part 2. A CASE on SUSER_SNAME(), without table access: the function runs at every
-- connection. APP_NAME() and HOST_NAME() would be easier to test, but the client writes
-- them, and any session could claim them.
CREATE FUNCTION dbo.ClassifyExport()
RETURNS sysname
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE WHEN SUSER_SNAME() = N'export_user' THEN N'Export' ELSE N'default' END;
END;
GO
ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = dbo.ClassifyExport);
ALTER RESOURCE GOVERNOR RECONFIGURE;
GO
SELECT p.name AS pool, p.cap_cpu_percent, p.max_memory_percent,
       g.name AS workload_group, g.max_dop, g.request_max_memory_grant_percent_numeric AS grant_percent,
       g.group_max_tempdb_data_mb
FROM sys.resource_governor_resource_pools AS p
JOIN sys.resource_governor_workload_groups AS g ON g.pool_id = p.pool_id
WHERE p.name = N'ExportPool';
SELECT OBJECT_NAME(classifier_function_id) AS classifier_function, is_enabled
FROM sys.resource_governor_configuration;
GO
-- Part 3, in this window: the export as sa, in the group default.
USE PachadataTraining;
SELECT TOP (100) ContactId, ModuleId, COUNT(*) AS Events,
       SUM(CAST(DurationSeconds AS bigint)) AS Seconds
FROM Elearning.Activity
GROUP BY ContactId, ModuleId
ORDER BY Seconds DESC;
GO
