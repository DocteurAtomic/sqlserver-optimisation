-- Clip D5.1: which group each session landed in. Runs on the throwaway container after
-- 01c-pools-and-groups.sql, once charge.sh has been started again. Reads only.
-- ci: skip (it needs the logins of 00-setup.sql)
-- A session keeps the group it was given when it connected: the sessions opened before
-- 01c stay in default until they reconnect.
USE master;
SET NOCOUNT ON;
GO
SELECT s.login_name, s.host_name, g.name AS workload_group, p.name AS pool
FROM sys.dm_exec_sessions AS s
JOIN sys.dm_resource_governor_workload_groups AS g ON g.group_id = s.group_id
JOIN sys.dm_resource_governor_resource_pools AS p ON p.pool_id = g.pool_id
WHERE s.is_user_process = 1
ORDER BY g.name, s.host_name;
GO
-- EXECUTE AS does not move a session: the classification ran when it connected. This
-- session, opened by sa, stays in default under the identity of report_user.
EXECUTE AS LOGIN = N'report_user';
DECLARE @who sysname = SUSER_SNAME();
REVERT;
SELECT @who AS identity_under_execute_as, g.name AS workload_group_of_this_session
FROM sys.dm_exec_sessions AS s
JOIN sys.dm_resource_governor_workload_groups AS g ON g.group_id = s.group_id
WHERE s.session_id = @@SPID;
