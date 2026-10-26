-- Clip D1.2: a max server memory above what the container gives. Runs in one session.
-- ci: skip (it changes the configuration of the instance, then puts it back)
-- The current value is kept, max server memory is raised to 16 GB, the target is read, then
-- the value found at the start is put back.
USE master;
SET NOCOUNT ON;
GO
CREATE TABLE #Before (value int);
INSERT #Before SELECT CONVERT(int, value) FROM sys.configurations WHERE name = N'max server memory (MB)';
EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure N'max server memory (MB)', 16384;
RECONFIGURE;
GO
WAITFOR DELAY '00:00:05';
-- 16 GB asked, in a container of 6 GB: the target stops at what the engine sees.
SELECT (SELECT value_in_use FROM sys.configurations WHERE name = N'max server memory (MB)') AS max_server_memory_mb,
       physical_memory_kb / 1024 AS physical_memory_mb,
       committed_target_kb / 1024 AS target_mb
FROM sys.dm_os_sys_info;
GO
DECLARE @v int = (SELECT value FROM #Before);
EXEC sys.sp_configure N'max server memory (MB)', @v;
RECONFIGURE;
DROP TABLE #Before;
GO
WAITFOR DELAY '00:00:05';
SELECT (SELECT value_in_use FROM sys.configurations WHERE name = N'max server memory (MB)') AS max_server_memory_mb,
       committed_target_kb / 1024 AS target_mb
FROM sys.dm_os_sys_info;
