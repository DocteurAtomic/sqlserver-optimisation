-- Run by install.sh. Creates master.dbo.reset_training, which every module's 00-setup.sql calls
-- to start from the delivered database, then restores the two databases if they are missing.
USE master;
GO
CREATE OR ALTER PROCEDURE dbo.reset_training
    @db sysname = N'PachadataTraining'  -- another name restores a separate copy
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @data nvarchar(260) = N'/var/opt/mssql/data/' + @db + N'.mdf',
            @log nvarchar(260) = N'/var/opt/mssql/data/' + @db + N'_log.ldf';
    DECLARE @q nvarchar(max), @n nvarchar(300) = QUOTENAME(@db);
    IF DB_ID(@db) IS NOT NULL
    BEGIN
        SET @q = N'ALTER DATABASE ' + @n + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
        EXEC (@q);
    END;
    RESTORE DATABASE @db
        FROM DISK = N'/var/opt/mssql/backup/PachadataTraining-2026-10.bak'
        WITH REPLACE,
             MOVE N'PachadataTraining' TO @data,
             MOVE N'PachadataTraining_log' TO @log;
    -- The backup is at level 160 (built on SQL Server 2022); the course runs at level 170.
    SET @q = N'ALTER DATABASE ' + @n + N' SET MULTI_USER; ALTER DATABASE ' + @n + N' SET COMPATIBILITY_LEVEL = 170;';
    EXEC (@q);
END;
GO
IF DB_ID(N'PachadataTraining') IS NULL
    EXEC dbo.reset_training;
ELSE
    PRINT 'PachadataTraining already exists: not restored.';
GO
IF DB_ID(N'LuminaQuant') IS NULL
    RESTORE DATABASE LuminaQuant
        FROM DISK = N'/var/opt/mssql/backup/LuminaQuant.bak'
        WITH MOVE N'LuminaQuant' TO N'/var/opt/mssql/data/LuminaQuant.mdf',
             MOVE N'LuminaQuant_log' TO N'/var/opt/mssql/data/LuminaQuant_log.ldf';
ELSE
    PRINT 'LuminaQuant already exists: not restored.';
GO
SELECT name, compatibility_level FROM sys.databases WHERE name IN (N'PachadataTraining', N'LuminaQuant');
