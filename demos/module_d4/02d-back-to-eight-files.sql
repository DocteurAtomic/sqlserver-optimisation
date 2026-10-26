-- Clip D4.2: back to the eight data files of the lab. Runs on the throwaway container, in
-- one session, after charge.sh has stopped (Ctrl+C) and after 02c-more-files.sql.
-- ci: skip (it removes files from tempdb: an instance change)
-- Each file added by 02c is emptied (its pages move to the other files), then removed;
-- SQL Server deletes the file from the disk. A file that does not exist is skipped.
USE tempdb;
SET NOCOUNT ON;
GO
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
GO
SELECT COUNT(*) AS tempdb_data_files FROM tempdb.sys.database_files WHERE type_desc = N'ROWS';
