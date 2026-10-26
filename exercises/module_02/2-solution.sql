-- Module 2 exercise: solution. Runs on the lab, in one session, after 1-start.sql.
-- It changes nothing in the end: part 3 rolls its transaction back.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- Part 1. A page of Contact.Contact.
-- 1.1 Where is the contact 1234? (%%physloc%% is undocumented.)
SELECT ContactId, LastName, FirstName,
       sys.fn_PhysLocFormatter(%%physloc%%) AS Location
FROM Contact.Contact
WHERE ContactId = 1234;

-- 1.2 The header of its page.
DECLARE @file int, @page int;
SELECT @file = plc.file_id, @page = plc.page_id
FROM Contact.Contact
CROSS APPLY sys.fn_PhysLocCracker(%%physloc%%) AS plc
WHERE ContactId = 1234;

SELECT page_type_desc, OBJECT_NAME(object_id) AS ObjectName, index_id, page_level,
       slot_count, free_bytes, prev_page_page_id, next_page_page_id
FROM sys.dm_db_page_info(DB_ID(), @file, @page, 'DETAILED');

-- 1.3 Rows per page and row size, leaf level of the clustered index.
SELECT index_level, page_count, record_count,
       CAST(1.0 * record_count / page_count AS decimal(6, 1)) AS rows_per_page,
       CAST(avg_record_size_in_bytes AS decimal(6, 1)) AS avg_record_bytes,
       CAST(avg_page_space_used_in_percent AS decimal(5, 1)) AS page_used_pct
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'Contact.Contact'), 1, NULL, 'DETAILED')
WHERE index_level = 0;
GO
-- Part 2. The same prospects in two tables, read cold then warm.
SELECT OBJECT_NAME(object_id) AS TableName, row_count, used_page_count
FROM sys.dm_db_partition_stats
WHERE object_id IN (OBJECT_ID(N'Contact.ProspectUS'), OBJECT_ID(N'Contact.ProspectUS_N'))
  AND index_id = 0;

SELECT c.name, t.name AS type_name, c.max_length
FROM sys.columns AS c
JOIN sys.types AS t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'Contact.ProspectUS_N') AND c.name = N'City';
GO
USE master;
ALTER DATABASE PachadataTraining SET OFFLINE WITH ROLLBACK IMMEDIATE;
ALTER DATABASE PachadataTraining SET ONLINE;
GO
USE PachadataTraining;
SET NOCOUNT ON;
SELECT wait_type, waiting_tasks_count, wait_time_ms
INTO #WaitsBefore
FROM sys.dm_exec_session_wait_stats
WHERE session_id = @@SPID;

SET STATISTICS IO, TIME ON;
SELECT COUNT(*) AS Prospects FROM Contact.ProspectUS WHERE City = 'Boston';      -- cold
SELECT COUNT(*) AS Prospects FROM Contact.ProspectUS WHERE City = 'Boston';      -- warm
SELECT COUNT(*) AS Prospects FROM Contact.ProspectUS_N WHERE City = N'Boston';   -- cold
SELECT COUNT(*) AS Prospects FROM Contact.ProspectUS_N WHERE City = N'Boston';   -- warm
SET STATISTICS IO, TIME OFF;

SELECT w.wait_type,
       w.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) AS waits,
       w.wait_time_ms - ISNULL(b.wait_time_ms, 0) AS wait_ms
FROM sys.dm_exec_session_wait_stats AS w
LEFT JOIN #WaitsBefore AS b ON b.wait_type = w.wait_type
WHERE w.session_id = @@SPID AND w.wait_type LIKE N'PAGEIOLATCH%';
GO
-- Part 3. The log of one transaction, while it is open.
BEGIN TRANSACTION;
UPDATE Contact.ProspectUS SET City = UPPER(City) WHERE City = 'Boston';
SELECT @@ROWCOUNT AS RowsChanged;

SELECT dt.database_transaction_log_record_count AS LogRecords,
       dt.database_transaction_log_bytes_used AS LogBytesUsed,
       dt.database_transaction_log_bytes_reserved AS LogBytesReserved
FROM sys.dm_tran_database_transactions AS dt
JOIN sys.dm_tran_session_transactions AS st ON st.transaction_id = dt.transaction_id
WHERE st.session_id = @@SPID AND dt.database_id = DB_ID();

CHECKPOINT;
SELECT d.log_reuse_wait_desc,
       (SELECT COUNT(*) FROM sys.dm_os_buffer_descriptors
        WHERE database_id = DB_ID() AND is_modified = 1) AS DirtyPagesAfterCheckpoint
FROM sys.databases AS d
WHERE d.database_id = DB_ID();

ROLLBACK;
SELECT COUNT(*) AS BostonUpperCase FROM Contact.ProspectUS WHERE City = 'BOSTON' COLLATE French_CS_AS;
