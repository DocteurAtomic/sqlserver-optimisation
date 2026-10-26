-- Module V7, clip 3: row versioning turned on. Runs on the lab, in one session, after
-- 00-setup.sql (the procedure as the setup left it: the call to the accounting software
-- inside the transaction).
-- ALTER DATABASE needs to be alone in the base: WITH ROLLBACK IMMEDIATE rolls back the
-- other sessions. Stop the load first.
USE master;
GO
ALTER DATABASE PachadataTraining SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO
USE PachadataTraining;
GO
SET NOCOUNT ON;
SELECT name, is_read_committed_snapshot_on, snapshot_isolation_state_desc,
       is_accelerated_database_recovery_on
FROM sys.databases
WHERE name = DB_NAME();
GO
-- Each modification now writes the previous version of the row to the version store,
-- in tempdb (ADR is off on this base).
BEGIN TRANSACTION;
UPDATE Enrollment.Invoice
SET ReminderLevel = 3 - ReminderLevel
WHERE InvoiceCode LIKE 'FA2026-%';
SELECT @@ROWCOUNT AS rows_updated;
SELECT DB_NAME(database_id) AS database_name, reserved_page_count, reserved_space_kb
FROM sys.dm_tran_version_store_space_usage
WHERE database_id = DB_ID();
ROLLBACK;
GO
