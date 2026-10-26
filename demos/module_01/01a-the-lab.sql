-- Clip 1.1: the lab. Runs on the lab, in one session; reads only.
USE master;
GO
-- The version and the edition of the engine.
SELECT SERVERPROPERTY('ProductVersion') AS ProductVersion,
       SERVERPROPERTY('ProductUpdateLevel') AS UpdateLevel,
       SERVERPROPERTY('Edition') AS Edition;
-- The two databases of the course, and their compatibility level.
SELECT name, compatibility_level, is_read_committed_snapshot_on, is_query_store_on
FROM sys.databases
WHERE name IN (N'PachadataTraining', N'LuminaQuant');
-- What the engine sees of the machine. The container is limited to 4 processors and 6 GB:
-- the engine still sees every processor of the host, and takes 80 % of the memory limit.
SELECT cpu_count, scheduler_count,
       physical_memory_kb / 1024 AS physical_memory_mb,
       committed_target_kb / 1024 AS target_memory_mb,
       container_type_desc, sqlserver_start_time
FROM sys.dm_os_sys_info;
