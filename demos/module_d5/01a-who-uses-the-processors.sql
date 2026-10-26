-- Clip D5.1: who uses the processors. Runs on the throwaway container while charge.sh runs
-- (alone, it returns the lab at rest). Reads only.
-- 1. What SQL Server sees: its schedulers, against the processors of the container.
-- 2. The requests running now, by login: the reports and the enrollment screen.
-- 3. The state of the resource governor: off, no classifier function, every user session in
--    the default workload group.
USE master;
SET NOCOUNT ON;
GO
-- 1. The engine counts the processors of the host, not the quota of the container: the lab
--    has four processors (cpus: 4 in compose.yaml), and SQL Server sees all those of the host.
SELECT cpu_count,
       (SELECT COUNT(*) FROM sys.dm_os_schedulers WHERE status = N'VISIBLE ONLINE') AS visible_schedulers,
       physical_memory_kb / 1024 AS memory_mb
FROM sys.dm_os_sys_info;
GO
-- 2. The running requests by login: how many, how many tasks, and the processor time they
--    have used so far (SQL Server counts the time a thread waits for the quota of the
--    container as processor time).
SELECT s.login_name,
       COUNT(*) AS requests,
       SUM(t.tasks) AS tasks,
       SUM(r.cpu_time) / 1000 AS cpu_s,
       MAX(r.dop) AS max_dop
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
CROSS APPLY (SELECT COUNT(*) AS tasks FROM sys.dm_os_tasks AS t
             WHERE t.session_id = r.session_id AND t.request_id = r.request_id) AS t
WHERE s.is_user_process = 1 AND r.session_id <> @@SPID
GROUP BY s.login_name
ORDER BY cpu_s DESC;
GO
-- 3. The governor: off, without a classifier function; the user sessions per workload group.
SELECT OBJECT_NAME(classifier_function_id) AS classifier_function, is_enabled
FROM sys.resource_governor_configuration;
SELECT g.name AS workload_group, s.login_name, COUNT(*) AS sessions
FROM sys.dm_exec_sessions AS s
JOIN sys.dm_resource_governor_workload_groups AS g ON g.group_id = s.group_id
WHERE s.is_user_process = 1
GROUP BY g.name, s.login_name
ORDER BY g.name, s.login_name;
