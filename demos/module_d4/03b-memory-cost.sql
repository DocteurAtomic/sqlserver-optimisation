-- Clip D4.3: what the memory-optimized metadata changes. Runs on the throwaway container,
-- in one session, after the restart that follows 03a-memory-optimized-metadata.sql, before
-- charge.sh is started again.
-- ci: skip (it expects the option of 03a, enabled at the previous start of the instance)
USE master;
SET NOCOUNT ON;
GO
-- 1. The option in use, and the line the error log writes when tempdb starts with it.
SELECT SERVERPROPERTY('IsTempdbMetadataMemoryOptimized') AS memory_optimized_metadata,
       value_in_use
FROM sys.configurations
WHERE name = N'tempdb metadata memory-optimized';
CREATE TABLE #Log (LogDate datetime, ProcessInfo nvarchar(50), Text nvarchar(4000));
INSERT INTO #Log EXEC sys.xp_readerrorlog 0, 1, N'memory-optimized metadata';
SELECT CONVERT(char(19), LogDate, 120) AS log_date, Text FROM #Log;
DROP TABLE #Log;

-- 2. The memory of In-Memory OLTP at rest, right after the start: the system tables of
--    tempdb now live there, in the memory of the instance.
SELECT type, SUM(pages_kb) / 1024 AS mb
FROM sys.dm_os_memory_clerks
WHERE type = N'MEMORYCLERK_XTP'
GROUP BY type;
GO
-- 3. The limit that breaks code: no columnstore index on a temporary table any more. The
--    statement fails with two messages, 11442 and 1750: this error is expected.
CREATE TABLE #Facts (SessionId int NOT NULL, Revenue decimal(12, 2) NOT NULL,
                     INDEX cci_Facts CLUSTERED COLUMNSTORE);
