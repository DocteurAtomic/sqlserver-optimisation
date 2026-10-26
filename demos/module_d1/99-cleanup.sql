-- Module D1, cleanup: puts the instance back as the lab was delivered. Runs in one session.
-- ci: skip (it changes the configuration of the instance)
-- Values read on a new container of the lab image (2025-CU7): max server memory
-- 2,147,483,647 MB, max degree of parallelism 0, cost threshold for parallelism 5, show
-- advanced options 0, process affinity AUTO. The database is restored by the next module.
USE master;
SET NOCOUNT ON;
GO
EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure N'max server memory (MB)', 2147483647;
EXEC sys.sp_configure N'max degree of parallelism', 0;
EXEC sys.sp_configure N'cost threshold for parallelism', 5;
RECONFIGURE;
EXEC sys.sp_configure N'show advanced options', 0;
RECONFIGURE;
ALTER SERVER CONFIGURATION SET PROCESS AFFINITY CPU = AUTO;
GO
SELECT name, value, value_in_use
FROM sys.configurations
WHERE name IN (N'max server memory (MB)', N'max degree of parallelism',
               N'cost threshold for parallelism', N'show advanced options')
ORDER BY name;
