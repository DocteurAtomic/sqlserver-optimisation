-- Module V4, cleanup. Runs on the lab, in one session, after the last clip and the exercise
-- of the module. It lasts a few seconds.
-- Restores LuminaQuant as delivered: the setup and the demos of the module changed it (the
-- index IX_Trade_ExecutedAt widened, MAXDOP 2, the procedure dbo.GetDailyTradeVolume and
-- the copy dbo.TradeColumnstore). The exercises of the other modules expect it as
-- setup/install.sh restored it.
USE master;
GO
IF DB_ID(N'LuminaQuant') IS NOT NULL
    ALTER DATABASE LuminaQuant SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
RESTORE DATABASE LuminaQuant
    FROM DISK = N'/var/opt/mssql/backup/LuminaQuant.bak'
    WITH REPLACE,
         MOVE N'LuminaQuant' TO N'/var/opt/mssql/data/LuminaQuant.mdf',
         MOVE N'LuminaQuant_log' TO N'/var/opt/mssql/data/LuminaQuant_log.ldf';
GO
ALTER DATABASE LuminaQuant SET MULTI_USER;
GO
SELECT name, compatibility_level, state_desc FROM sys.databases WHERE name = N'LuminaQuant';
