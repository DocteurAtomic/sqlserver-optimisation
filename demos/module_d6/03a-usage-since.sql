-- Clip D6.3: since when the usage counters of the indexes run.
-- Runs on the lab, in one session, after the scripts of clip D6.2. Takes the database
-- offline and back online, so no other session may use it.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The counters start with the instance, or with the database.
SELECT sqlserver_start_time FROM sys.dm_os_sys_info;
SELECT MAX(restore_date) AS LastRestore
FROM msdb.dbo.restorehistory
WHERE destination_database_name = DB_NAME();
-- 2. What is left of the module so far, on the indexes of Marketing.Delivery: 02b took the
--    database offline twice.
SELECT i.name AS IndexName, u.user_seeks, u.user_scans, u.user_lookups, u.user_updates
FROM sys.indexes AS i
LEFT JOIN sys.dm_db_index_usage_stats AS u
    ON u.database_id = DB_ID() AND u.object_id = i.object_id AND u.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'Marketing.Delivery')
ORDER BY i.index_id;
GO
-- 3. The database offline and back online, as at a restart of the instance: its rows leave
--    the view, and the suggestions of missing indexes leave theirs.
USE master;
GO
ALTER DATABASE PachadataTraining SET OFFLINE WITH ROLLBACK IMMEDIATE;
ALTER DATABASE PachadataTraining SET ONLINE;
GO
SELECT COUNT(*) AS UsageRows
FROM sys.dm_db_index_usage_stats WHERE database_id = DB_ID(N'PachadataTraining');
SELECT COUNT(*) AS MissingIndexRows
FROM sys.dm_db_missing_index_details WHERE database_id = DB_ID(N'PachadataTraining');
GO
