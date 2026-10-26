-- Clip D5.2: the soft limit. Runs on the throwaway container, while charge.sh runs, after
-- 01c-pools-and-groups.sql. Changes the instance: 99-cleanup.sql removes it.
-- ci: skip (it changes the resource governor of the instance)
-- MAX_CPU_PERCENT = 20 on the pool of the reports. A pool setting applies at once to the
-- sessions already in the pool: no need to restart the load. Play 01b-measure-load.sql next.
USE master;
GO
ALTER RESOURCE POOL ReportPool WITH (MAX_CPU_PERCENT = 20);
ALTER RESOURCE GOVERNOR RECONFIGURE;
GO
SELECT name, min_cpu_percent, max_cpu_percent, cap_cpu_percent
FROM sys.resource_governor_resource_pools
WHERE name = N'ReportPool';
