-- Clip D7.3, the watch query in an Agent job, every five minutes. Changes the instance:
-- runs on your own server or on a throwaway container, not on a shared lab.
-- ci: skip (it creates an Agent job, an object of the instance; not played on the lab)
-- The alarms go to a table of PachadataDBA (module 1). On Linux, the Agent has no alerts
-- (Learn, "Editions and supported features of SQL Server 2025 on Linux"): the job writes
-- the rows, and Database Mail, if configured, can send them.
-- The job and the table are dropped at the end of the script, commented out.
USE PachadataDBA;
GO
IF OBJECT_ID(N'dbo.WatchAlarm') IS NULL
    CREATE TABLE dbo.WatchAlarm (
        AlarmTime datetime2(0) NOT NULL DEFAULT SYSDATETIME(),
        Alarm nvarchar(40) NOT NULL,
        DatabaseName sysname NULL,
        Detail nvarchar(400) NOT NULL
    );
GO
USE msdb;
GO
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'PachadataDBA - watch')
    EXEC msdb.dbo.sp_delete_job @job_name = N'PachadataDBA - watch';
EXEC msdb.dbo.sp_add_job @job_name = N'PachadataDBA - watch',
     @description = N'Blocked requests, full logs, idle open transactions (module D7).',
     @owner_login_name = N'sa';
-- The step: the three alarms of 03d-watch-query.sql, inserted into dbo.WatchAlarm.
EXEC msdb.dbo.sp_add_jobstep @job_name = N'PachadataDBA - watch',
     @step_name = N'Watch', @subsystem = N'TSQL', @database_name = N'PachadataDBA',
     @command = N'INSERT dbo.WatchAlarm (Alarm, DatabaseName, Detail)
SELECT N''blocked request'', DB_NAME(r.database_id),
       CONCAT(s.host_name, N'' ('', r.session_id, N'') waits '', r.wait_time / 1000, N'' s on '',
              r.wait_type, N'', blocked by session '', r.blocking_session_id)
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
WHERE r.blocking_session_id <> 0 AND r.wait_time > 30000;
INSERT dbo.WatchAlarm (Alarm, DatabaseName, Detail)
SELECT N''log almost full'', d.name,
       CONCAT(ls.cntr_value, N'' % used, waiting for '', d.log_reuse_wait_desc)
FROM sys.databases AS d
JOIN sys.dm_os_performance_counters AS ls
  ON ls.counter_name = N''Percent Log Used'' AND ls.instance_name = d.name
WHERE d.database_id > 4 AND ls.cntr_value > 80;
INSERT dbo.WatchAlarm (Alarm, DatabaseName, Detail)
SELECT N''idle open transaction'', DB_NAME(dt.database_id),
       CONCAT(s.host_name, N'' ('', s.session_id, N''), open since '',
              CONVERT(varchar(19), dt.database_transaction_begin_time, 120))
FROM sys.dm_tran_database_transactions AS dt
JOIN sys.dm_tran_session_transactions AS st ON st.transaction_id = dt.transaction_id
JOIN sys.dm_exec_sessions AS s ON s.session_id = st.session_id
WHERE s.status = N''sleeping''
  AND dt.database_transaction_begin_time < DATEADD(MINUTE, -10, SYSDATETIME());';
EXEC msdb.dbo.sp_add_jobschedule @job_name = N'PachadataDBA - watch', @name = N'Every 5 minutes',
     @freq_type = 4, @freq_interval = 1, @freq_subday_type = 4, @freq_subday_interval = 5;
EXEC msdb.dbo.sp_add_jobserver @job_name = N'PachadataDBA - watch', @server_name = N'(local)';
GO
-- To remove it:
-- EXEC msdb.dbo.sp_delete_job @job_name = N'PachadataDBA - watch';
-- DROP TABLE PachadataDBA.dbo.WatchAlarm;
