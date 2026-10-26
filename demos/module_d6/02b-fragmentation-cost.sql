-- Clip D6.2: what reading ix_Delivery_ContactId costs, cold then warm.
-- Runs on the lab, in one session. Takes the database offline and back online to empty its
-- pages from the buffer pool (DBCC DROPCLEANBUFFERS would empty the whole instance), so no
-- other session may use the database. Played twice: after 02a-physical-stats.sql, on the
-- fragmented index, then after 02c-reorganize.sql.
USE master;
GO
ALTER DATABASE PachadataTraining SET OFFLINE WITH ROLLBACK IMMEDIATE;
ALTER DATABASE PachadataTraining SET ONLINE;
GO
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- The number of deliveries per contact, read in the order of the index. The hint keeps the
-- same index and the same plan from one measure to the next; MAXDOP 1 keeps one thread.
-- The reads of the data file before the cold query.
SELECT num_of_reads, num_of_bytes_read, io_stall_read_ms
INTO #before
FROM sys.dm_io_virtual_file_stats(DB_ID(), 1);
SET STATISTICS IO, TIME ON;
-- Cold: every page comes from the data file.
SELECT COUNT(*) AS Contacts
FROM (SELECT ContactId, COUNT(*) AS Deliveries
      FROM Marketing.Delivery WITH (INDEX (ix_Delivery_ContactId))
      GROUP BY ContactId) AS x
OPTION (MAXDOP 1);
SET STATISTICS IO, TIME OFF;
-- What the cold query asked of the data file, and how long it waited for it. The host may
-- serve these reads from its own file cache, which the lab does not empty.
SELECT f.num_of_reads - b.num_of_reads AS FileReads,
       (f.num_of_bytes_read - b.num_of_bytes_read) / 1048576 AS MBRead,
       f.io_stall_read_ms - b.io_stall_read_ms AS ReadStallMs
FROM sys.dm_io_virtual_file_stats(DB_ID(), 1) AS f
CROSS JOIN #before AS b;
DROP TABLE #before;
SET STATISTICS IO, TIME ON;
-- Warm: every page is in memory.
SELECT COUNT(*) AS Contacts
FROM (SELECT ContactId, COUNT(*) AS Deliveries
      FROM Marketing.Delivery WITH (INDEX (ix_Delivery_ContactId))
      GROUP BY ContactId) AS x
OPTION (MAXDOP 1);
SET STATISTICS IO, TIME OFF;
GO
-- The memory the index now takes in the buffer pool.
SELECT COUNT(*) AS BufferPages, COUNT(*) * 8 / 1024 AS BufferMB
FROM sys.dm_os_buffer_descriptors AS b
JOIN sys.allocation_units AS au ON au.allocation_unit_id = b.allocation_unit_id
JOIN sys.partitions AS p ON p.hobt_id = au.container_id
WHERE b.database_id = DB_ID()
  AND p.object_id = OBJECT_ID(N'Marketing.Delivery')
  AND p.index_id = INDEXPROPERTY(OBJECT_ID(N'Marketing.Delivery'), N'ix_Delivery_ContactId', 'IndexId');
GO
