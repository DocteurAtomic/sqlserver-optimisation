-- ci: skip (two sessions: run 04a-open-transaction.sql first, in another window)
-- Clip 2.2, session 2: work that writes to the log while session 1 keeps its transaction
-- open, then a checkpoint. The log cannot be truncated behind the oldest active transaction.
USE PachadataTraining;
SET NOCOUNT ON;
GO
SELECT CAST(used_log_space_in_percent AS decimal(5, 1)) AS LogUsedPct,
       used_log_space_in_bytes / 1048576 AS LogUsedMb
FROM sys.dm_db_log_space_usage;
GO
-- Some log: every phone number of the one million US prospects reversed, then put back.
UPDATE Contact.ProspectUS SET Phone = REVERSE(Phone);
UPDATE Contact.ProspectUS SET Phone = REVERSE(Phone);
CHECKPOINT;
GO
-- The log stays used after the checkpoint, and the reason is named.
SELECT CAST(u.used_log_space_in_percent AS decimal(5, 1)) AS LogUsedPct,
       u.used_log_space_in_bytes / 1048576 AS LogUsedMb,
       d.log_reuse_wait_desc
FROM sys.dm_db_log_space_usage AS u
JOIN sys.databases AS d ON d.database_id = u.database_id;

-- The oldest active transaction of the database, and its session.
DBCC OPENTRAN WITH TABLERESULTS, NO_INFOMSGS;

SELECT s.session_id, t.transaction_id, t.name, t.transaction_begin_time,
       dt.database_transaction_log_bytes_used AS LogBytesUsed
FROM sys.dm_tran_active_transactions AS t
JOIN sys.dm_tran_session_transactions AS s ON s.transaction_id = t.transaction_id
JOIN sys.dm_tran_database_transactions AS dt ON dt.transaction_id = t.transaction_id
WHERE dt.database_id = DB_ID() AND s.session_id <> @@SPID;
GO
-- Once session 1 has committed (after its 60 seconds), the next checkpoint truncates.
WAITFOR DELAY '00:01:00';
CHECKPOINT;
SELECT CAST(u.used_log_space_in_percent AS decimal(5, 1)) AS LogUsedPct,
       u.used_log_space_in_bytes / 1048576 AS LogUsedMb,
       d.log_reuse_wait_desc
FROM sys.dm_db_log_space_usage AS u
JOIN sys.databases AS d ON d.database_id = u.database_id;
