-- Clip D7.3, the watch query: what should have woken someone up during the night. Runs on
-- the lab, in one session. Reads only: it returns one row per alarm, none on a quiet lab.
-- During the night of charge.sh, it returns the blocked import, the log and the open
-- transaction. 03e-watch-job.sql runs the same three queries every five minutes.
USE master;
SET NOCOUNT ON;
GO
CREATE TABLE #Alarm (Alarm nvarchar(40), DatabaseName sysname NULL, Detail nvarchar(400));
-- Alarm 1: a request blocked for more than 30 seconds.
INSERT #Alarm
SELECT N'blocked request', DB_NAME(r.database_id),
       CONCAT(s.host_name, N' (', r.session_id, N') waits ', r.wait_time / 1000, N' s on ',
              r.wait_type, N', blocked by session ', r.blocking_session_id)
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
WHERE r.blocking_session_id <> 0 AND r.wait_time > 30000;
-- Alarm 2: a log more than 80 % used, read in the counters of the Databases object, which
-- have one instance per database (sys.dm_db_log_space_usage only sees the current one).
INSERT #Alarm
SELECT N'log almost full', d.name,
       CONCAT(ls.cntr_value, N' % used, waiting for ', d.log_reuse_wait_desc)
FROM sys.databases AS d
JOIN sys.dm_os_performance_counters AS ls
  ON ls.counter_name = N'Percent Log Used' AND ls.instance_name = d.name
WHERE d.database_id > 4 AND ls.cntr_value > 80;
-- Alarm 3: a transaction open for more than 10 minutes on a session that runs nothing.
INSERT #Alarm
SELECT N'idle open transaction', DB_NAME(dt.database_id),
       CONCAT(s.host_name, N' (', s.session_id, N'), open since ',
              CONVERT(varchar(19), dt.database_transaction_begin_time, 120))
FROM sys.dm_tran_database_transactions AS dt
JOIN sys.dm_tran_session_transactions AS st ON st.transaction_id = dt.transaction_id
JOIN sys.dm_exec_sessions AS s ON s.session_id = st.session_id
WHERE s.status = N'sleeping'
  AND dt.database_transaction_begin_time < DATEADD(MINUTE, -10, SYSDATETIME());
SELECT Alarm, DatabaseName, Detail FROM #Alarm;
GO
