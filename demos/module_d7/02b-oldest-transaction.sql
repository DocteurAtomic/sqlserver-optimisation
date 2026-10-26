-- Clip D7.2, the log and the oldest transaction. Runs on the lab, in one session, after
-- charge.sh has played the night. Reads only; without the night, the steps return the log as
-- it is and no open transaction.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- Step 1. The oldest active transaction of the database, as DBCC OPENTRAN gives it.
DBCC OPENTRAN WITH TABLERESULTS, NO_INFOMSGS;
GO
-- Step 2. The transactions that have written to the log of this database, the oldest first:
-- their session, their age, and the log they hold. In SIMPLE recovery, nothing after the
-- first log record of the oldest one can be reused.
SELECT st.session_id, s.host_name,
       dt.database_transaction_begin_time AS first_write,
       DATEDIFF(SECOND, dt.database_transaction_begin_time, SYSDATETIME()) AS open_s,
       dt.database_transaction_log_record_count AS log_records,
       dt.database_transaction_log_bytes_used / 1024 AS log_kb
FROM sys.dm_tran_database_transactions AS dt
JOIN sys.dm_tran_session_transactions AS st ON st.transaction_id = dt.transaction_id
JOIN sys.dm_exec_sessions AS s ON s.session_id = st.session_id
WHERE dt.database_id = DB_ID()
  AND dt.database_transaction_begin_time IS NOT NULL
ORDER BY dt.database_transaction_begin_time;
GO
-- Step 3. A checkpoint does not help while the transaction is open: the log stays used.
CHECKPOINT;
SELECT d.log_reuse_wait_desc,
       CAST(l.total_log_size_in_bytes / 1048576.0 AS decimal(10, 1)) AS log_mb,
       CAST(l.used_log_space_in_percent AS decimal(5, 1)) AS used_pct
FROM sys.databases AS d
CROSS JOIN sys.dm_db_log_space_usage AS l
WHERE d.database_id = DB_ID();
GO
