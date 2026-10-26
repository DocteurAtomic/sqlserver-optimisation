-- Clip 1.3: a baseline over one minute. Runs on the lab, in one session, while charge.sh runs
-- (it also runs alone: the values are then those of an idle lab). Lasts one minute.
USE PachadataDBA;
GO
EXEC dbo.TakeSnapshot;
WAITFOR DELAY '00:01:00';
EXEC dbo.TakeSnapshot;
GO
-- The two last snapshots.
DECLARE @t1 datetime2(0) = (SELECT MAX(SnapshotTime) FROM dbo.CounterSnapshot);
DECLARE @t0 datetime2(0) = (SELECT MAX(SnapshotTime) FROM dbo.CounterSnapshot WHERE SnapshotTime < @t1);
DECLARE @s int = DATEDIFF(second, @t0, @t1);

-- The counters: per second over the interval for the cumulative ones, the last value for
-- the others.
SELECT c1.CounterName,
       CASE WHEN c1.CounterName LIKE N'%/sec'
            THEN (c1.CounterValue - c0.CounterValue) / @s
            ELSE c1.CounterValue END AS Value,
       CASE WHEN c1.CounterName LIKE N'%/sec' THEN N'per second' ELSE N'at the end' END AS Unit
FROM dbo.CounterSnapshot AS c1
JOIN dbo.CounterSnapshot AS c0 ON c0.CounterName = c1.CounterName AND c0.SnapshotTime = @t0
WHERE c1.SnapshotTime = @t1
ORDER BY c1.CounterName;

-- The waits of the interval, the longest first. The signal part is the time spent waiting
-- for a processor once the resource was there.
SELECT TOP (6) w1.WaitType,
       w1.WaitingTasks - w0.WaitingTasks AS Waits,
       (w1.WaitTimeMs - w0.WaitTimeMs) / 1000 AS WaitTimeS,
       CAST(100.0 * (w1.SignalWaitTimeMs - w0.SignalWaitTimeMs)
            / NULLIF(w1.WaitTimeMs - w0.WaitTimeMs, 0) AS decimal(5, 1)) AS SignalPct
FROM dbo.WaitSnapshot AS w1
JOIN dbo.WaitSnapshot AS w0 ON w0.WaitType = w1.WaitType AND w0.SnapshotTime = @t0
WHERE w1.SnapshotTime = @t1
  AND w1.WaitTimeMs > w0.WaitTimeMs
ORDER BY w1.WaitTimeMs - w0.WaitTimeMs DESC;
