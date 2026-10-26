-- Clip D5.3: a smaller grant for each report. Runs on the throwaway container while
-- charge.sh runs, after 02c-cap-for-three-processors.sql. Changes the instance:
-- 99-cleanup.sql removes it.
-- ci: skip (it changes the resource governor of the instance)
-- REQUEST_MAX_MEMORY_GRANT_PERCENT = 10 on the group of the reports (25 by default): each
-- report asks for at most a tenth of the memory of its pool, so more of them run at once
-- instead of waiting, and none starts with its minimum. A group setting applies to the next
-- requests of the sessions already in the group. Play 03a-memory-grants.sql and
-- 01b-measure-load.sql next.
USE master;
GO
ALTER WORKLOAD GROUP Reports WITH (REQUEST_MAX_MEMORY_GRANT_PERCENT = 10);
ALTER RESOURCE GOVERNOR RECONFIGURE;
GO
SELECT name, request_max_memory_grant_percent_numeric AS grant_percent, max_dop
FROM sys.resource_governor_workload_groups
WHERE name = N'Reports';
