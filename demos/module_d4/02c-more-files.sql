-- Clip D4.2: the usual advice, measured. Runs on the throwaway container, in one session,
-- while charge.sh runs. Lasts a little more than one minute.
-- ci: skip (it adds files to tempdb: an instance change, under the load)
-- Thirty seconds of the portal with the eight data files of the lab, then thirty seconds
-- with sixteen. The added files cannot be removed under the load (emptying a file waits for
-- the schema locks of the temporary tables it holds): 02d-back-to-eight-files.sql removes
-- them once charge.sh has stopped.
USE master;
SET NOCOUNT ON;
GO
-- A temporary procedure that measures thirty seconds: calls of the portal, page latch waits.
CREATE PROCEDURE #Measure @label varchar(20)
AS
SET NOCOUNT ON;
DECLARE @t0 datetime2 = SYSDATETIME(), @calls0 bigint, @ex0 bigint, @sh0 bigint, @up0 bigint;
SELECT @calls0 = ISNULL(SUM(execution_count), 0)
FROM sys.dm_exec_procedure_stats
WHERE object_id = OBJECT_ID(N'PachadataTraining.Course.GetAttendanceSheet')
  AND database_id = DB_ID(N'PachadataTraining');
SELECT @ex0 = SUM(IIF(wait_type = N'PAGELATCH_EX', wait_time_ms, 0)),
       @sh0 = SUM(IIF(wait_type = N'PAGELATCH_SH', wait_time_ms, 0)),
       @up0 = SUM(IIF(wait_type = N'PAGELATCH_UP', wait_time_ms, 0))
FROM sys.dm_os_wait_stats
WHERE wait_type IN (N'PAGELATCH_EX', N'PAGELATCH_SH', N'PAGELATCH_UP');
WAITFOR DELAY '00:00:30';
DECLARE @s decimal(9, 3) = DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0;
SELECT @label AS tempdb_files,
       CAST((SUM(ps.execution_count) - @calls0) / @s AS decimal(9, 0)) AS calls_per_s,
       (SELECT CAST((SUM(IIF(wait_type = N'PAGELATCH_EX', wait_time_ms, 0)) - @ex0) / 1000.0 / @s AS decimal(9, 1))
        FROM sys.dm_os_wait_stats WHERE wait_type = N'PAGELATCH_EX') AS ex_wait_s_per_s,
       (SELECT CAST((SUM(IIF(wait_type = N'PAGELATCH_SH', wait_time_ms, 0)) - @sh0) / 1000.0 / @s AS decimal(9, 1))
        FROM sys.dm_os_wait_stats WHERE wait_type = N'PAGELATCH_SH') AS sh_wait_s_per_s,
       (SELECT CAST((SUM(IIF(wait_type = N'PAGELATCH_UP', wait_time_ms, 0)) - @up0) / 1000.0 / @s AS decimal(9, 1))
        FROM sys.dm_os_wait_stats WHERE wait_type = N'PAGELATCH_UP') AS up_wait_s_per_s
FROM sys.dm_exec_procedure_stats AS ps
WHERE ps.object_id = OBJECT_ID(N'PachadataTraining.Course.GetAttendanceSheet')
  AND ps.database_id = DB_ID(N'PachadataTraining');
GO
-- 1. Eight data files, as on the lab.
EXEC #Measure @label = '8';
GO
-- 2. Eight more files, same size and growth as the others (the size of tempdev).
DECLARE @i int = 9, @sql nvarchar(400),
        @size_mb int = (SELECT size / 128 FROM tempdb.sys.database_files WHERE file_id = 1);
WHILE @i <= 16
BEGIN
    SET @sql = N'ALTER DATABASE tempdb ADD FILE (NAME = tempdev' + CAST(@i AS nvarchar(2))
             + N', FILENAME = ''/var/opt/mssql/data/tempdb' + CAST(@i AS nvarchar(2))
             + N'.ndf'', SIZE = ' + CAST(@size_mb AS nvarchar(10)) + N'MB, FILEGROWTH = 64MB);';
    EXEC (@sql);
    SET @i += 1;
END;
GO
EXEC #Measure @label = '16';
GO
