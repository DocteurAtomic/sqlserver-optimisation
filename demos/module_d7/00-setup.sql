-- Module D7, setup. Runs on the lab, in one session, before the first clip of the module.
-- It lasts a few seconds. Then ./demos/module_d7/charge.sh plays the night.
-- Needs the database PachadataDBA of module 1 (demos/module_01/03a-baseline-tables.sql).
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. Query Store: emptied (the queries of the restore), interval of one minute and capture of
--    every query, as in the delivered backup (in production: 60 minutes and AUTO).
-- 3. The transaction log is brought back to 128 MB, the size it has on the production
--    server: the delivered backup has a log of 1.2 GB, which the night would not fill.
--    It keeps its automatic growth of 50 MB.
-- 4. The evening snapshot of the baseline: dbo.TakeSnapshot of module 1 copies the waits and
--    a few counters of the instance into PachadataDBA. The morning routine compares with it.
-- The problems of the module are played by charge.sh, which says what it does in its header.
-- In short, three things go wrong during the night, and they are revealed in clip D7.3:
--   - the accountant postpones the due date of the October invoices in SSMS, inside a
--     transaction she never commits: the bank payments import and the payments of the
--     customer area wait for her locks, and the log can no longer be truncated while the
--     e-learning import keeps writing;
--   - the night maintenance rebuilds the indexes of Contact.Contact, which recompiles
--     Contact.GetContactByName, and the first call that follows asks for N'Simon', the most
--     frequent name: every search of the back office then scans the table (module 4).
USE master;
GO
IF DB_ID(N'PachadataDBA') IS NULL
    THROW 50000, N'PachadataDBA is missing: run demos/module_01/03a-baseline-tables.sql first.', 1;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
SET NOCOUNT ON;
ALTER DATABASE CURRENT SET QUERY_STORE (OPERATION_MODE = READ_WRITE,
    INTERVAL_LENGTH_MINUTES = 1, QUERY_CAPTURE_MODE = ALL);
ALTER DATABASE CURRENT SET QUERY_STORE CLEAR;
GO
USE PachadataTraining;
SET NOCOUNT ON;
CHECKPOINT;
DBCC SHRINKFILE (PachadataTraining_log, 128) WITH NO_INFOMSGS;
GO
-- The log as the night will find it.
USE PachadataTraining;
SELECT name, type_desc, size / 128 AS size_mb, growth / 128 AS growth_mb
FROM sys.database_files;
SELECT CAST(total_log_size_in_bytes / 1048576.0 AS decimal(10, 1)) AS log_mb,
       CAST(used_log_space_in_percent AS decimal(5, 1)) AS used_pct
FROM sys.dm_db_log_space_usage;
GO
-- The evening snapshot.
EXEC PachadataDBA.dbo.TakeSnapshot;
SELECT MAX(SnapshotTime) AS evening_snapshot, COUNT(*) AS wait_types
FROM PachadataDBA.dbo.WaitSnapshot
WHERE SnapshotTime = (SELECT MAX(SnapshotTime) FROM PachadataDBA.dbo.WaitSnapshot);
GO
