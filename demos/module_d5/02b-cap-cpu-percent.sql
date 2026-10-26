-- Clip D5.2: the hard limit. Runs on the throwaway container, while charge.sh runs, after
-- 02a-max-cpu-percent.sql. Changes the instance: 99-cleanup.sql removes it.
-- ci: skip (it changes the resource governor of the instance)
-- CAP_CPU_PERCENT = 20, back to MAX_CPU_PERCENT = 100. Play 01b-measure-load.sql next.
-- The last column says what 20 % means on your lab: the percentages of the governor are
-- shares of the schedulers SQL Server sees, not of the four processors of the container.
USE master;
GO
ALTER RESOURCE POOL ReportPool WITH (MAX_CPU_PERCENT = 100, CAP_CPU_PERCENT = 20);
ALTER RESOURCE GOVERNOR RECONFIGURE;
GO
SELECT name, max_cpu_percent, cap_cpu_percent,
       (SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = N'VISIBLE ONLINE') AS visible_schedulers,
       CAST(cap_cpu_percent / 100.0 * (SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = N'VISIBLE ONLINE')
            AS decimal(5, 2)) AS processors_allowed
FROM sys.resource_governor_resource_pools
WHERE name = N'ReportPool';
GO
