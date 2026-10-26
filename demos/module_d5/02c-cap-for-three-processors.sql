-- Clip D5.2: a cap computed from the schedulers. Runs on the throwaway container, while
-- charge.sh runs, after 02b-cap-cpu-percent.sql. Changes the instance: 99-cleanup.sql
-- removes it.
-- ci: skip (it changes the resource governor of the instance)
-- The reports may use three of the four processors of the container. The cap is a share of
-- the schedulers SQL Server sees: 300 / schedulers, rounded up (14 % with 22 schedulers).
-- Play 01b-measure-load.sql next.
USE master;
GO
DECLARE @schedulers int = (SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = N'VISIBLE ONLINE');
DECLARE @cap int = CEILING(300.0 / @schedulers);
IF @cap > 100 SET @cap = 100;
DECLARE @sql nvarchar(200) = N'ALTER RESOURCE POOL ReportPool WITH (CAP_CPU_PERCENT = '
                           + CAST(@cap AS nvarchar(3)) + N');';
EXEC (@sql);
ALTER RESOURCE GOVERNOR RECONFIGURE;
SELECT name, max_cpu_percent, cap_cpu_percent, @schedulers AS visible_schedulers,
       CAST(cap_cpu_percent / 100.0 * @schedulers AS decimal(5, 2)) AS processors_allowed
FROM sys.resource_governor_resource_pools
WHERE name = N'ReportPool';
