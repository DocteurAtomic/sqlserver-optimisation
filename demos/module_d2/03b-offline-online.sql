-- Clip D2.3: what the VLFs cost when the database starts. Runs on the lab, in one session.
-- It takes the database offline then online, which runs its recovery: every other session in
-- the database is disconnected. Never on a production server.
USE master;
SET NOCOUNT ON;
GO
DECLARE @mark datetime = GETDATE(), @start datetime2;
ALTER DATABASE PachadataTraining SET OFFLINE WITH ROLLBACK IMMEDIATE;
SET @start = SYSDATETIME();
ALTER DATABASE PachadataTraining SET ONLINE;
SELECT DATEDIFF(MILLISECOND, @start, SYSDATETIME()) AS online_ms;

-- What the error log says about this start: from "Starting up database" to the start of the
-- redo, the engine reads the log and builds the list of its VLFs.
DROP TABLE IF EXISTS #errorlog;
CREATE TABLE #errorlog (log_date datetime, process_info nvarchar(64), text nvarchar(4000));
INSERT INTO #errorlog
EXEC master.dbo.xp_readerrorlog 0, 1, N'PachadataTraining';
SELECT CONVERT(char(12), log_date, 114) AS at_time, LEFT(text, 90) AS message
FROM #errorlog
WHERE log_date >= @mark
  AND (text LIKE N'Starting up database%' OR text LIKE N'Parallel redo is started%'
       OR text LIKE N'Recovery completed%' OR text LIKE N'%virtual log files%')
ORDER BY log_date;
GO
