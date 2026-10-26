-- Clip 1.3: the baseline tables, and the procedure that fills them. Runs on the lab, in one
-- session. Creates the database PachadataDBA, which no 00-setup.sql restores: the baseline
-- survives the modules, and module D3 schedules its collection with an Agent job.
USE master;
GO
IF DB_ID(N'PachadataDBA') IS NULL
    CREATE DATABASE PachadataDBA;
GO
USE PachadataDBA;
GO
-- One row per wait type and per snapshot. The view is cumulative since the start of the
-- service: a snapshot alone means nothing, two snapshots give an interval.
IF OBJECT_ID(N'dbo.WaitSnapshot') IS NULL
    CREATE TABLE dbo.WaitSnapshot (
        SnapshotTime datetime2(0) NOT NULL,
        WaitType nvarchar(60) NOT NULL,
        WaitingTasks bigint NOT NULL,
        WaitTimeMs bigint NOT NULL,
        SignalWaitTimeMs bigint NOT NULL,
        CONSTRAINT pk_WaitSnapshot PRIMARY KEY (SnapshotTime, WaitType)
    );
-- One row per counter and per snapshot. The "/sec" counters are cumulative as well;
-- Page life expectancy and User Connections are a value at the time of the snapshot.
IF OBJECT_ID(N'dbo.CounterSnapshot') IS NULL
    CREATE TABLE dbo.CounterSnapshot (
        SnapshotTime datetime2(0) NOT NULL,
        CounterName nvarchar(128) NOT NULL,
        CounterValue bigint NOT NULL,
        CONSTRAINT pk_CounterSnapshot PRIMARY KEY (SnapshotTime, CounterName)
    );
GO
CREATE OR ALTER PROCEDURE dbo.TakeSnapshot
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now datetime2(0) = SYSDATETIME();
    -- The waits of the queries. The idle waits of the system tasks (sleeps, queues waiting
    -- for work, Extended Events, Service Broker, availability groups) are left out: they
    -- grow even on an instance that does nothing.
    INSERT dbo.WaitSnapshot (SnapshotTime, WaitType, WaitingTasks, WaitTimeMs, SignalWaitTimeMs)
    SELECT @now, wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE waiting_tasks_count > 0
      AND wait_type NOT LIKE N'%SLEEP%'
      AND wait_type NOT LIKE N'%QUEUE%'
      AND wait_type NOT LIKE N'%IDLE%'
      AND wait_type NOT LIKE N'XE[_]%'
      AND wait_type NOT LIKE N'BROKER[_]%'
      AND wait_type NOT LIKE N'HADR[_]%'
      AND wait_type NOT LIKE N'SQLTRACE[_]%'
      AND wait_type NOT IN (N'WAITFOR', N'DISPATCHER_QUEUE_SEMAPHORE', N'CHECKPOINT_QUEUE',
                            N'REQUEST_FOR_DEADLOCK_SEARCH', N'LOGMGR_QUEUE',
                            N'DIRTY_PAGE_POLL', N'SP_SERVER_DIAGNOSTICS_SLEEP',
                            N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', N'PWAIT_EXTENSIBILITY_CLEANUP_TASK',
                            N'SOS_WORK_DISPATCHER', N'PARALLEL_REDO_WORKER_WAIT_WORK');
    -- A few counters of the instance.
    INSERT dbo.CounterSnapshot (SnapshotTime, CounterName, CounterValue)
    SELECT @now, RTRIM(counter_name), cntr_value
    FROM sys.dm_os_performance_counters
    WHERE (object_name LIKE N'%:SQL Statistics%'
           AND counter_name IN (N'Batch Requests/sec', N'SQL Compilations/sec'))
       OR (object_name LIKE N'%:Buffer Manager%'
           AND counter_name IN (N'Page lookups/sec', N'Page reads/sec', N'Page life expectancy'))
       OR (object_name LIKE N'%:General Statistics%'
           AND counter_name = N'User Connections');
END;
GO
SELECT name FROM sys.tables ORDER BY name;
