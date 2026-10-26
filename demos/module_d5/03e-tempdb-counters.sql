-- Clip D5.3: the counters after the error 1138. Runs on the throwaway container, as sa,
-- after 03d-temp-table-as-report-user.sql. Reads only.
-- ci: skip (the columns of tempdb space governance exist from SQL Server 2025, and the
-- group Reports from 01c-pools-and-groups.sql)
USE master;
SET NOCOUNT ON;
GO
SELECT g.name AS workload_group, c.group_max_tempdb_data_mb AS limit_mb,
       g.tempdb_data_space_kb / 1024 AS tempdb_now_mb,
       g.peak_tempdb_data_space_kb / 1024 AS tempdb_peak_mb,
       g.total_tempdb_data_limit_violation_count AS violations
FROM sys.dm_resource_governor_workload_groups AS g
JOIN sys.resource_governor_workload_groups AS c ON c.group_id = g.group_id
WHERE g.name IN (N'default', N'Reports', N'Entry');
