-- Module D1, setup. Runs in one session, before the first clip of the module.
-- ci: skip (it changes the configuration of the instance)
-- The video plays the whole module on a throwaway copy of the lab (container sqlopt-d1, same
-- image, 6 GB and 4 processors). On your lab, play it, then 99-cleanup.sql at the end of the
-- module: instance settings survive the restore of a database.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. The problem of the module, at two scopes.
--    Instance: max server memory (MB) is set to 1,024 MB, a quarter of what the engine could
--    take in a 6 GB container. max degree of parallelism (0) and cost threshold for
--    parallelism (5) are written at their default values, which nobody had changed.
--    Database: MAXDOP is set to 0 (2 in the delivered backup), so the instance setting applies:
--    a parallel query may take one thread per processor the engine sees.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure N'max server memory (MB)', 1024;
EXEC sys.sp_configure N'max degree of parallelism', 0;
EXEC sys.sp_configure N'cost threshold for parallelism', 5;
RECONFIGURE;
GO
USE PachadataTraining;
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;
GO
SELECT name, value_in_use
FROM sys.configurations
WHERE name IN (N'max server memory (MB)', N'max degree of parallelism',
               N'cost threshold for parallelism')
ORDER BY name;
SELECT name, value
FROM sys.database_scoped_configurations
WHERE name = N'MAXDOP';
