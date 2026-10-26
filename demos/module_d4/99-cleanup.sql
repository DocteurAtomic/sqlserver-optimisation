-- Module D4, cleanup: puts the instance back as the lab was delivered. Runs in one session,
-- after charge.sh has stopped. It shuts the instance down: start the container afterwards
-- (docker start sqloptcourse; the video: podman start sqlopt-d4).
-- ci: skip (it changes a server configuration and shuts the instance down)
-- Values read on a new container of the lab image (2025-CU7): memory-optimized tempdb
-- metadata off, eight data files of 8 MB with a growth of 64 MB. 00b-presize-tempdb.sql
-- set them to 256 MB: DBCC SHRINKFILE brings each one back to 8 MB, and for tempdb the new
-- size is also the size of the next starts (measured on 26 October 2026). The files that
-- 02c-more-files.sql adds are removed here too, if 02d-back-to-eight-files.sql was not
-- played. The procedure of the module lives in PachadataTraining: the next module's
-- 00-setup.sql restores the database.
USE master;
SET NOCOUNT ON;
GO
ALTER SERVER CONFIGURATION SET MEMORY_OPTIMIZED TEMPDB_METADATA = OFF;
GO
USE tempdb;
DECLARE @i int = 9, @name sysname, @sql nvarchar(400);
WHILE @i <= 16
BEGIN
    SET @name = N'tempdev' + CAST(@i AS nvarchar(2));
    IF EXISTS (SELECT 1 FROM tempdb.sys.database_files WHERE name = @name)
    BEGIN
        SET @sql = N'DBCC SHRINKFILE (' + @name + N', EMPTYFILE) WITH NO_INFOMSGS; '
                 + N'ALTER DATABASE tempdb REMOVE FILE ' + @name + N';';
        EXEC (@sql);
    END;
    SET @i += 1;
END;
DECLARE @shrink nvarchar(max) = N'';
SELECT @shrink += N'DBCC SHRINKFILE (' + QUOTENAME(name) + N', 8) WITH NO_INFOMSGS; '
FROM tempdb.sys.database_files
WHERE type_desc = N'ROWS' AND size > 8 * 128;
EXEC (@shrink);
USE master;
GO
SELECT value, value_in_use,
       (SELECT COUNT(*) FROM tempdb.sys.database_files WHERE type_desc = N'ROWS') AS tempdb_data_files,
       (SELECT MAX(size) / 128 FROM sys.master_files WHERE database_id = 2 AND type_desc = N'ROWS') AS startup_size_mb
FROM sys.configurations
WHERE name = N'tempdb metadata memory-optimized';
GO
SHUTDOWN;
