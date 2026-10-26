-- Module D2 exercise: solution. Runs on your lab, in one session, after 1-start.sql.
-- Part 1 takes PachadataTraining offline then online twice, to empty its pages from the
-- cache. Parts 2 and 3 create the database ExoStorage, then drop it at the end.
-- It takes about fifteen seconds.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-------------------------------------------------------------------------------------------
-- Part 1. The I/O of two known reads, cold, measured on their interval.
-------------------------------------------------------------------------------------------
-- 1a. A sequential read: counting the prospects of a city reads the whole heap.
USE master;
ALTER DATABASE PachadataTraining SET OFFLINE WITH ROLLBACK IMMEDIATE;
ALTER DATABASE PachadataTraining SET ONLINE;
GO
USE PachadataTraining;
DROP TABLE IF EXISTS #io_before;
SELECT file_id, num_of_reads, num_of_bytes_read, io_stall_read_ms
INTO #io_before
FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL);

SELECT COUNT(*) AS prospects FROM Contact.ProspectUS WHERE City = 'Boston';

SELECT N'sequential' AS read_kind, FILE_NAME(b.file_id) AS file_name,
       v.num_of_reads - b.num_of_reads AS reads,
       (v.num_of_bytes_read - b.num_of_bytes_read) / 1048576 AS read_mb,
       (v.num_of_bytes_read - b.num_of_bytes_read) / 1024
            / NULLIF(v.num_of_reads - b.num_of_reads, 0) AS kb_per_read,
       CAST((v.io_stall_read_ms - b.io_stall_read_ms) * 1.0
            / NULLIF(v.num_of_reads - b.num_of_reads, 0) AS decimal(10, 2)) AS ms_per_read
FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL) AS v
JOIN #io_before AS b ON b.file_id = v.file_id;
GO
-- 1b. 2,000 lookups by key at random in Marketing.Delivery, cold.
USE master;
ALTER DATABASE PachadataTraining SET OFFLINE WITH ROLLBACK IMMEDIATE;
ALTER DATABASE PachadataTraining SET ONLINE;
GO
USE PachadataTraining;
DROP TABLE IF EXISTS #io_before;
SELECT file_id, num_of_reads, num_of_bytes_read, io_stall_read_ms
INTO #io_before
FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL);

DECLARE @i int = 0, @contact int;
WHILE @i < 2000
BEGIN
    SELECT @contact = ContactId
    FROM Marketing.Delivery
    WHERE DeliveryId = 1 + ABS(CHECKSUM(NEWID())) % 4018304;
    SET @i += 1;
END;

SELECT N'lookups' AS read_kind, FILE_NAME(b.file_id) AS file_name,
       v.num_of_reads - b.num_of_reads AS reads,
       (v.num_of_bytes_read - b.num_of_bytes_read) / 1048576 AS read_mb,
       (v.num_of_bytes_read - b.num_of_bytes_read) / 1024
            / NULLIF(v.num_of_reads - b.num_of_reads, 0) AS kb_per_read,
       CAST((v.io_stall_read_ms - b.io_stall_read_ms) * 1.0
            / NULLIF(v.num_of_reads - b.num_of_reads, 0) AS decimal(10, 2)) AS ms_per_read
FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL) AS v
JOIN #io_before AS b ON b.file_id = v.file_id;
GO
-- The sequential read reads few, large blocks (read-ahead groups contiguous pages, up to
-- 512 KB a read), and its average latency is higher, because many reads are in flight at
-- once. The lookups read one page or one extent at a time, and wait for each: that is the
-- latency a transactional application feels. A ms_per_read read without kb_per_read can
-- accuse a disk that is only serving scans. The log file reads nothing in either case.

-------------------------------------------------------------------------------------------
-- Part 2. A log that grows by 10 %, its VLFs, its fix, and the creation rule. The new
-- database takes the log of model: 8 MB on SQL Server 2025.
-------------------------------------------------------------------------------------------
USE master;
GO
DROP DATABASE IF EXISTS ExoStorage;
GO
CREATE DATABASE ExoStorage;
ALTER DATABASE ExoStorage SET RECOVERY SIMPLE;
ALTER DATABASE ExoStorage MODIFY FILE (NAME = ExoStorage, SIZE = 512MB, FILEGROWTH = 256MB);
ALTER DATABASE ExoStorage MODIFY FILE (NAME = ExoStorage_log, FILEGROWTH = 10%);
GO
USE ExoStorage;
SET NOCOUNT ON;
CREATE TABLE dbo.Payload (
    PayloadId int IDENTITY NOT NULL CONSTRAINT pk_Payload PRIMARY KEY,
    Filler    char(500) NOT NULL
);
SELECT COUNT(*) AS vlf_before, CAST(SUM(vlf_size_mb) AS decimal(10, 1)) AS log_mb
FROM sys.dm_db_log_info(DB_ID());
GO
-- 2a. One transaction of 400,000 rows of 500 bytes.
DECLARE @start datetime2 = SYSDATETIME();
INSERT INTO dbo.Payload (Filler)
SELECT TOP (400000) 'x'
FROM sys.all_columns AS a CROSS JOIN sys.all_columns AS b;
SELECT DATEDIFF(MILLISECOND, @start, SYSDATETIME()) AS insert_ms;
GO
-- 2b. The VLFs: how many, and how big. A growth of 10 % grows with the file, and so do the
--     VLFs it creates.
SELECT COUNT(*) AS vlf, CAST(SUM(vlf_size_mb) AS decimal(10, 1)) AS log_mb,
       CAST(MIN(vlf_size_mb) AS decimal(10, 2)) AS smallest_mb,
       CAST(MAX(vlf_size_mb) AS decimal(10, 2)) AS largest_mb
FROM sys.dm_db_log_info(DB_ID());
GO
-- 2c. One VLF per growth here (each growth of 10 % is less than an eighth of the file):
--     the sizes of the VLFs, from the start of the file, are the successive growths.
SELECT TOP (12) file_id, CAST(vlf_begin_offset / 1048576.0 AS decimal(10, 1)) AS starts_at_mb,
       CAST(vlf_size_mb AS decimal(10, 2)) AS vlf_size_mb
FROM sys.dm_db_log_info(DB_ID())
ORDER BY vlf_begin_offset;
GO
-- 2d. The fix: checkpoint (simple recovery model), shrink, grow back in one step, fixed growth.
CHECKPOINT;
DBCC SHRINKFILE (ExoStorage_log, 1) WITH NO_INFOMSGS;
SELECT COUNT(*) AS vlf_after_shrink, CAST(SUM(vlf_size_mb) AS decimal(10, 1)) AS log_mb
FROM sys.dm_db_log_info(DB_ID());
ALTER DATABASE ExoStorage MODIFY FILE (NAME = ExoStorage_log, SIZE = 512MB, FILEGROWTH = 256MB);
SELECT COUNT(*) AS vlf_fixed, CAST(SUM(vlf_size_mb) AS decimal(10, 1)) AS log_mb
FROM sys.dm_db_log_info(DB_ID());
GO
-- 2e. The rule, checked: from a log of 64 MB, a growth of 64 MB, then of 65 MB from the same
--     size. Learn announces one VLF for a growth of 64 MB or less since SQL Server 2022.
CHECKPOINT;
DBCC SHRINKFILE (ExoStorage_log, 1) WITH NO_INFOMSGS;
ALTER DATABASE ExoStorage MODIFY FILE (NAME = ExoStorage_log, SIZE = 64MB);
DECLARE @vlf int = (SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID()));
ALTER DATABASE ExoStorage MODIFY FILE (NAME = ExoStorage_log, SIZE = 128MB);
SELECT N'64 MB on 64 MB' AS growth, COUNT(*) - @vlf AS vlf_added FROM sys.dm_db_log_info(DB_ID());
GO
CHECKPOINT;
DBCC SHRINKFILE (ExoStorage_log, 1) WITH NO_INFOMSGS;
ALTER DATABASE ExoStorage MODIFY FILE (NAME = ExoStorage_log, SIZE = 64MB);
DECLARE @vlf int = (SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID()));
ALTER DATABASE ExoStorage MODIFY FILE (NAME = ExoStorage_log, SIZE = 129MB);
SELECT N'65 MB on 64 MB' AS growth, COUNT(*) - @vlf AS vlf_added FROM sys.dm_db_log_info(DB_ID());
GO

-------------------------------------------------------------------------------------------
-- Part 3. A filegroup of two equal files.
-------------------------------------------------------------------------------------------
-- 3a. The filegroup Archive, two files of the same size and growth, in the default data
--     folder of the instance; the whole group grows at once.
USE master;
DECLARE @path nvarchar(260) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(260));
DECLARE @sql nvarchar(max) = N'
ALTER DATABASE ExoStorage ADD FILEGROUP Archive;
ALTER DATABASE ExoStorage ADD FILE
    (NAME = ExoStorage_Archive1, FILENAME = N''' + @path + N'ExoStorage_Archive1.ndf'', SIZE = 128MB, FILEGROWTH = 64MB),
    (NAME = ExoStorage_Archive2, FILENAME = N''' + @path + N'ExoStorage_Archive2.ndf'', SIZE = 128MB, FILEGROWTH = 64MB)
TO FILEGROUP Archive;
ALTER DATABASE ExoStorage MODIFY FILEGROUP Archive AUTOGROW_ALL_FILES;';
EXEC (@sql);
GO
-- 3b. Moving the table: rebuild its clustered index in the new filegroup. DROP_EXISTING
--     keeps the name and the primary key; ONLINE = ON leaves it readable meanwhile
--     (Enterprise and Developer editions).
USE ExoStorage;
CREATE UNIQUE CLUSTERED INDEX pk_Payload ON dbo.Payload (PayloadId)
WITH (DROP_EXISTING = ON, ONLINE = ON) ON Archive;
GO
-- 3c. Proportional fill: both files received the same share.
SELECT fg.name AS filegroup_name, f.name AS file_name, f.size / 128 AS size_mb,
       FILEPROPERTY(f.name, 'SpaceUsed') / 128 AS used_mb
FROM sys.database_files AS f
LEFT JOIN sys.filegroups AS fg ON fg.data_space_id = f.data_space_id
ORDER BY f.file_id;
GO
-- 3d. Twice as many rows: the files fill together, and grow together.
INSERT INTO dbo.Payload (Filler) SELECT Filler FROM dbo.Payload;
SELECT fg.name AS filegroup_name, f.name AS file_name, f.size / 128 AS size_mb,
       FILEPROPERTY(f.name, 'SpaceUsed') / 128 AS used_mb
FROM sys.database_files AS f
LEFT JOIN sys.filegroups AS fg ON fg.data_space_id = f.data_space_id
ORDER BY f.file_id;
GO
-- Cleanup: the exercise database disappears.
USE master;
ALTER DATABASE ExoStorage SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE ExoStorage;
GO
