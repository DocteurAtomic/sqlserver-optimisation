-- Clip D3.4: what the job collected, interval by interval. Runs on the lab, in one session;
-- it only reads PachadataDBA (created by demos/module_01/03a-baseline-tables.sql).
USE PachadataDBA;
SET NOCOUNT ON;
GO
-- 1. The job history: one line per run of the job (step 0 is the job outcome).
SELECT TOP (5) msdb.dbo.agent_datetime(h.run_date, h.run_time) AS run_at, h.run_status, h.message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'PachadataDBA - snapshot' AND h.step_id = 0
ORDER BY h.instance_id DESC;

-- 2. The counters of the last hour, per interval between two snapshots: the cumulative ones
--    per second, Page life expectancy as it was at the end of the interval.
WITH c AS (
    SELECT SnapshotTime, CounterName, CounterValue,
           LAG(SnapshotTime) OVER (PARTITION BY CounterName ORDER BY SnapshotTime) AS PreviousTime,
           LAG(CounterValue) OVER (PARTITION BY CounterName ORDER BY SnapshotTime) AS PreviousValue
    FROM dbo.CounterSnapshot
    WHERE SnapshotTime > DATEADD(HOUR, -1, SYSDATETIME())
)
SELECT CONVERT(char(8), CAST(SnapshotTime AS time(0))) AS interval_end,
       DATEDIFF(SECOND, MIN(PreviousTime), SnapshotTime) AS seconds,
       MAX(CASE WHEN CounterName = N'Batch Requests/sec'
                THEN (CounterValue - PreviousValue) / DATEDIFF(SECOND, PreviousTime, SnapshotTime) END) AS batches_per_s,
       MAX(CASE WHEN CounterName = N'SQL Compilations/sec'
                THEN (CounterValue - PreviousValue) / DATEDIFF(SECOND, PreviousTime, SnapshotTime) END) AS compilations_per_s,
       MAX(CASE WHEN CounterName = N'Page life expectancy' THEN CounterValue END) AS ple_s
FROM c
WHERE PreviousTime IS NOT NULL
GROUP BY SnapshotTime
ORDER BY SnapshotTime;

-- 3. The journal waits and the yields of each interval.
WITH w AS (
    SELECT SnapshotTime, WaitType,
           WaitTimeMs - LAG(WaitTimeMs) OVER (PARTITION BY WaitType ORDER BY SnapshotTime) AS WaitMs
    FROM dbo.WaitSnapshot
    WHERE SnapshotTime > DATEADD(HOUR, -1, SYSDATETIME())
)
SELECT CONVERT(char(8), CAST(SnapshotTime AS time(0))) AS interval_end,
       MAX(CASE WHEN WaitType = N'WRITELOG' THEN WaitMs END) AS writelog_ms,
       MAX(CASE WHEN WaitType = N'PREEMPTIVE_OS_FLUSHFILEBUFFERS' THEN WaitMs END) AS flushfilebuffers_ms,
       MAX(CASE WHEN WaitType = N'SOS_SCHEDULER_YIELD' THEN WaitMs END) AS sos_scheduler_yield_ms
FROM w
WHERE WaitMs IS NOT NULL
GROUP BY SnapshotTime
ORDER BY SnapshotTime;
