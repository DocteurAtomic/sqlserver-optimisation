-- Clip D3.4: the baseline of module 1, collected by an Agent job. Runs in one session.
-- ci: skip (it creates an Agent job, an object of the instance; 99-cleanup.sql drops it)
-- Needs the database PachadataDBA, created by demos/module_01/03a-baseline-tables.sql, and
-- the SQL Server Agent running (MSSQL_AGENT_ENABLED in the compose.yaml of the lab).
-- The job runs every minute, to see results within the clip; on a production server, every
-- five or fifteen minutes is enough to compare one day with another.
USE msdb;
SET NOCOUNT ON;
GO
IF DB_ID(N'PachadataDBA') IS NULL
    THROW 50000, N'PachadataDBA is missing: run demos/module_01/03a-baseline-tables.sql first.', 1;
GO
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'PachadataDBA - snapshot')
    EXEC msdb.dbo.sp_delete_job @job_name = N'PachadataDBA - snapshot';

EXEC msdb.dbo.sp_add_job
     @job_name = N'PachadataDBA - snapshot',
     @description = N'Snapshot of the waits and counters of the instance into PachadataDBA (module D3).',
     @owner_login_name = N'sa';

-- Step 1: the snapshot, by the procedure of module 1.
EXEC msdb.dbo.sp_add_jobstep
     @job_name = N'PachadataDBA - snapshot',
     @step_name = N'Take the snapshot',
     @subsystem = N'TSQL',
     @database_name = N'PachadataDBA',
     @command = N'EXEC dbo.TakeSnapshot;',
     @on_success_action = 3;  -- go to the next step

-- Step 2: keep 30 days. Without a purge, the table grows by a few hundred rows per snapshot.
EXEC msdb.dbo.sp_add_jobstep
     @job_name = N'PachadataDBA - snapshot',
     @step_name = N'Purge the snapshots older than 30 days',
     @subsystem = N'TSQL',
     @database_name = N'PachadataDBA',
     @command = N'DELETE dbo.WaitSnapshot WHERE SnapshotTime < DATEADD(DAY, -30, SYSDATETIME());
DELETE dbo.CounterSnapshot WHERE SnapshotTime < DATEADD(DAY, -30, SYSDATETIME());';

-- Every day, every minute (freq_subday_type 4: minutes).
EXEC msdb.dbo.sp_add_jobschedule
     @job_name = N'PachadataDBA - snapshot',
     @name = N'Every minute',
     @freq_type = 4, @freq_interval = 1,
     @freq_subday_type = 4, @freq_subday_interval = 1;

-- The job runs on this server.
EXEC msdb.dbo.sp_add_jobserver @job_name = N'PachadataDBA - snapshot', @server_name = N'(local)';
GO
SELECT j.name, j.enabled, s.name AS schedule_name, s.freq_subday_interval AS every_minutes,
       ja.next_scheduled_run_date
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobschedules AS js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules AS s ON s.schedule_id = js.schedule_id
LEFT JOIN msdb.dbo.sysjobactivity AS ja ON ja.job_id = j.job_id
 AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
WHERE j.name = N'PachadataDBA - snapshot';
