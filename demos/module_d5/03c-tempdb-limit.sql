-- Clip D5.3: the tempdb space of a workload group (SQL Server 2025). Runs on the throwaway
-- container, after 03b-grant-percent.sql. Changes the instance: 99-cleanup.sql removes it.
-- ci: skip (it changes the resource governor of the instance; SQL Server 2025 only)
-- 1. What each group has used of tempdb since the start of the instance: the counters work
--    without any limit.
-- 2. GROUP_MAX_TEMPDB_DATA_MB = 256 on the group of the reports. Play
--    03d-temp-table-as-report-user.sql next, connected as report_user, then
--    03e-tempdb-counters.sql.
USE master;
SET NOCOUNT ON;
GO
SELECT name AS workload_group,
       tempdb_data_space_kb / 1024 AS tempdb_now_mb,
       peak_tempdb_data_space_kb / 1024 AS tempdb_peak_mb,
       total_tempdb_data_limit_violation_count AS violations
FROM sys.dm_resource_governor_workload_groups
WHERE name IN (N'default', N'Reports', N'Entry');
GO
ALTER WORKLOAD GROUP Reports WITH (GROUP_MAX_TEMPDB_DATA_MB = 256);
ALTER RESOURCE GOVERNOR RECONFIGURE;
GO
SELECT name, group_max_tempdb_data_mb
FROM sys.resource_governor_workload_groups
WHERE name = N'Reports';
