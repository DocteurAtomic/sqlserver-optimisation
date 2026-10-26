-- Clip D4.3: memory-optimized tempdb metadata, enabled. Runs on the throwaway container,
-- in one session, after charge.sh has stopped (Ctrl+C): SHUTDOWN waits for the running
-- batches to end, and the loops of the portal last ten minutes.
-- ci: skip (it changes a server configuration and shuts the instance down)
-- The option exists since SQL Server 2019. It turns the system tables of tempdb that hold
-- the metadata of temporary objects into latch-free, non-durable memory-optimized tables.
-- It takes effect at the next start of the instance. Restart the container afterwards:
-- docker start sqloptcourse (the video: podman start sqlopt-d4).
USE master;
SET NOCOUNT ON;
GO
SELECT N'before' AS step, SERVERPROPERTY('IsTempdbMetadataMemoryOptimized') AS memory_optimized_metadata,
       value, value_in_use
FROM sys.configurations
WHERE name = N'tempdb metadata memory-optimized';
GO
ALTER SERVER CONFIGURATION SET MEMORY_OPTIMIZED TEMPDB_METADATA = ON;
GO
-- The configuration is recorded; the property still says 0 until the restart.
SELECT N'after ALTER' AS step, SERVERPROPERTY('IsTempdbMetadataMemoryOptimized') AS memory_optimized_metadata,
       value, value_in_use
FROM sys.configurations
WHERE name = N'tempdb metadata memory-optimized';
GO
-- A clean stop: SQL Server writes a checkpoint in every database, then stops.
SHUTDOWN;
