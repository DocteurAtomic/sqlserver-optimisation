-- Module D2, setup. Runs in one session on the lab, before the first clip of the module.
-- It takes about fifteen seconds. It only changes the database: the next module's
-- 00-setup.sql restores it, and nothing is left on the instance.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. Runs yesterday's nightly job once (the update of clip D2.1), while the log is still the
--    delivered one: the first update of a row adds its row-versioning tag (the database runs
--    under RCSI), and tonight's run must not pay for that.
-- 3. The problem of the module, the files as a careless maintenance left them: the
--    transaction log is shrunk to its minimum (about 13 MB) and set to grow by 1 MB at a
--    time; the data file is set to grow by 10 %.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
SET NOCOUNT ON;
UPDATE Elearning.Activity
SET DurationSeconds = DurationSeconds + 1
WHERE EventTypeCode = 'VIDE';
CHECKPOINT;
DBCC SHRINKFILE (PachadataTraining_log, 1) WITH NO_INFOMSGS;
ALTER DATABASE PachadataTraining MODIFY FILE (NAME = PachadataTraining_log, FILEGROWTH = 1MB);
ALTER DATABASE PachadataTraining MODIFY FILE (NAME = PachadataTraining, FILEGROWTH = 10%);
GO
SELECT name, type_desc, size / 128 AS size_mb,
       CASE WHEN is_percent_growth = 1 THEN CONCAT(growth, ' %')
            ELSE CONCAT(growth / 128, ' MB') END AS growth
FROM sys.database_files;
SELECT COUNT(*) AS vlf FROM sys.dm_db_log_info(DB_ID());
