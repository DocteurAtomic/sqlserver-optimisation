-- Clip D7.1, the morning routine, step 1: the waits of the instance since the evening.
-- Runs on the lab, in one session, after charge.sh has played the night. It takes a
-- snapshot into PachadataDBA (module 1) and compares it with the evening one.
-- On a production server, the Agent job of module D3 takes a snapshot every 15 minutes, and
-- @since is DATEADD(HOUR, -24, SYSDATETIME()). On the lab, the evening is the time
-- 00-setup.sql restored PachadataTraining, read from the restore history.
USE PachadataDBA;
SET NOCOUNT ON;
GO
-- One second first: snapshots are keyed by the second, and the evening one may be that recent.
WAITFOR DELAY '00:00:01';
EXEC dbo.TakeSnapshot;
GO
DECLARE @since datetime2(0) = (SELECT MAX(restore_date) FROM msdb.dbo.restorehistory
                               WHERE destination_database_name = N'PachadataTraining');
DECLARE @t0 datetime2(0) = (SELECT MIN(SnapshotTime) FROM dbo.WaitSnapshot WHERE SnapshotTime >= @since);
DECLARE @t1 datetime2(0) = (SELECT MAX(SnapshotTime) FROM dbo.WaitSnapshot);
SELECT @t0 AS evening, @t1 AS morning, DATEDIFF(SECOND, @t0, @t1) AS seconds;

-- The waits between the two snapshots, the longest first. A wait type absent from the
-- evening snapshot started during the night.
SELECT TOP (8) w1.WaitType,
       w1.WaitingTasks - ISNULL(w0.WaitingTasks, 0) AS Waits,
       (w1.WaitTimeMs - ISNULL(w0.WaitTimeMs, 0)) / 1000 AS WaitTimeS,
       (w1.WaitTimeMs - ISNULL(w0.WaitTimeMs, 0))
           / NULLIF(w1.WaitingTasks - ISNULL(w0.WaitingTasks, 0), 0) AS AvgWaitMs
FROM dbo.WaitSnapshot AS w1
LEFT JOIN dbo.WaitSnapshot AS w0 ON w0.WaitType = w1.WaitType AND w0.SnapshotTime = @t0
WHERE w1.SnapshotTime = @t1
  AND w1.WaitTimeMs > ISNULL(w0.WaitTimeMs, 0)
ORDER BY w1.WaitTimeMs - ISNULL(w0.WaitTimeMs, 0) DESC;

-- The lock waits, all modes together: a wait is counted when it starts, and its time when
-- it ends. A session still blocked this morning adds one to Waits and nothing to the time.
SELECT SUM(w1.WaitingTasks - ISNULL(w0.WaitingTasks, 0)) AS LockWaits,
       SUM(w1.WaitTimeMs - ISNULL(w0.WaitTimeMs, 0)) / 1000 AS LockWaitTimeS
FROM dbo.WaitSnapshot AS w1
LEFT JOIN dbo.WaitSnapshot AS w0 ON w0.WaitType = w1.WaitType AND w0.SnapshotTime = @t0
WHERE w1.SnapshotTime = @t1 AND w1.WaitType LIKE N'LCK[_]M[_]%';
GO
