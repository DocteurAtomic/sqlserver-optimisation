-- Module D4 exercise: solution. Runs on your lab, in one session (window 1), after
-- 1-start.sql. Start 2-forgotten-transaction.sql in window 2 just before part 1, question 3,
-- as the comment there says. Drops ExoTempdb at the end. Lasts about five minutes, most of
-- it spent waiting for the cleanup of the version store. Nothing here changes the instance.
USE ExoTempdb;
SET NOCOUNT ON;
GO
-------------------------------------------------------------------------------------------
-- Part 1. What fills tempdb.
-------------------------------------------------------------------------------------------
-- 1. A temporary table: user objects.
SELECT ProspectId, FirstName, LastName, Address, ZipCode, City, Phone, Email
INTO #Prospect
FROM dbo.Prospect;
GO
-- sys.dm_db_session_space_usage is updated at the end of each task: read it in the next
-- batch. The pages deallocated during the build are those of the intermediate allocations;
-- what is left is the table.
SELECT user_objects_alloc_page_count AS user_alloc, user_objects_dealloc_page_count AS user_dealloc,
       internal_objects_alloc_page_count AS internal_alloc, internal_objects_dealloc_page_count AS internal_dealloc
FROM sys.dm_db_session_space_usage
WHERE session_id = @@SPID;
SELECT SUM(user_object_reserved_page_count)     / 128 AS user_objects_mb,
       SUM(internal_object_reserved_page_count) / 128 AS internal_objects_mb,
       SUM(version_store_reserved_page_count)   / 128 AS version_store_mb
FROM tempdb.sys.dm_db_file_space_usage;
GO
-- 2. A sort that spills: internal objects, allocated during the sort and all deallocated at
--    its end. In SSMS, the actual plan shows a warning on the Sort operator.
DECLARE @Email varchar(100);
SELECT @Email = Email
FROM dbo.Prospect
ORDER BY Email, LastName
OPTION (MAX_GRANT_PERCENT = 0.1);
GO
SELECT user_objects_alloc_page_count AS user_alloc, user_objects_dealloc_page_count AS user_dealloc,
       internal_objects_alloc_page_count AS internal_alloc, internal_objects_dealloc_page_count AS internal_dealloc
FROM sys.dm_db_session_space_usage
WHERE session_id = @@SPID;
GO
-- 3. Window 2 runs 2-forgotten-transaction.sql (start it now). Under READ_COMMITTED_SNAPSHOT,
--    each updated row leaves its previous version in the version store of tempdb.
WAITFOR DELAY '00:00:03';
UPDATE dbo.Prospect SET Phone = CONCAT('1-', Phone) WHERE ProspectId > 1;
GO
SELECT DB_NAME(database_id) AS database_name, reserved_page_count / 128 AS version_store_mb
FROM sys.dm_tran_version_store_space_usage
WHERE reserved_page_count > 0;
SELECT session_id, transaction_sequence_num, elapsed_time_seconds, is_snapshot
FROM sys.dm_tran_active_snapshot_database_transactions;
GO
-- The cleanup of the version store runs about once a minute. A minute and a half later, the
-- versions are still there: the transaction of window 2 began before the UPDATE and may
-- still need them.
WAITFOR DELAY '00:01:30';
SELECT DB_NAME(database_id) AS database_name, reserved_page_count / 128 AS version_store_mb
FROM sys.dm_tran_version_store_space_usage
WHERE reserved_page_count > 0;
GO
-- Window 2 commits two minutes and a half after it started, about a minute after the
-- previous reading. Two minutes and a quarter more, and a cleanup has run since the commit:
-- the versions are freed.
WAITFOR DELAY '00:02:15';
SELECT DB_NAME(database_id) AS database_name, reserved_page_count / 128 AS version_store_mb
FROM sys.dm_tran_version_store_space_usage
WHERE reserved_page_count > 0;
SELECT COUNT(*) AS databases_with_versions
FROM sys.dm_tran_version_store_space_usage
WHERE reserved_page_count > 0;
DROP TABLE IF EXISTS #Prospect;
GO
-------------------------------------------------------------------------------------------
-- Part 2. A procedure that creates its temporary table at each call.
-------------------------------------------------------------------------------------------
-- A temporary procedure that calls dbo.GetMailingBatch 2,000 times and returns the
-- temporary tables really created by the instance during the calls, read in Temp Tables
-- Creation Rate. In SSMS, tick "Discard results after execution" first (Query Options,
-- Results, Grid): each call returns its fifty prospects.
CREATE PROCEDURE #Run2000
AS
SET NOCOUNT ON;
DECLARE @zip TABLE (n int IDENTITY PRIMARY KEY, ZipCode varchar(10));
INSERT INTO @zip (ZipCode) SELECT DISTINCT ZipCode FROM dbo.Prospect WHERE ZipCode IS NOT NULL;
DECLARE @i int = 0, @n int = (SELECT COUNT(*) FROM @zip), @z varchar(10), @c0 bigint,
        @t0 datetime2 = SYSDATETIME();
SELECT @c0 = cntr_value FROM sys.dm_os_performance_counters
WHERE RTRIM(object_name) LIKE N'%:General Statistics' AND RTRIM(counter_name) = N'Temp Tables Creation Rate';
WHILE @i < 2000
BEGIN
    SELECT @z = ZipCode FROM @zip WHERE n = 1 + @i % @n;
    EXEC dbo.GetMailingBatch @ZipCode = @z;
    SET @i += 1;
END;
SELECT cntr_value - @c0 AS temp_tables_created, DATEDIFF(millisecond, @t0, SYSDATETIME()) AS duration_ms
FROM sys.dm_os_performance_counters
WHERE RTRIM(object_name) LIKE N'%:General Statistics' AND RTRIM(counter_name) = N'Temp Tables Creation Rate';
GO
-- 1. The procedure as it is: its primary key has a name (CONSTRAINT pk_Batch).
EXEC #Run2000;
GO
-- 2. The same table with an unnamed primary key: SQL Server can cache it between calls.
--    The named constraint has a second defect: two sessions that create the table at the
--    same time collide on the name of the constraint (message 2714, CREATE TABLE on Learn).
CREATE OR ALTER PROCEDURE dbo.GetMailingBatch
    @ZipCode varchar(10)
AS
SET NOCOUNT ON;
CREATE TABLE #Batch (
    ProspectId int NOT NULL PRIMARY KEY,
    LastName varchar(50) NULL,
    City varchar(50) NULL
);
INSERT INTO #Batch (ProspectId, LastName, City)
SELECT TOP (50) ProspectId, LastName, City
FROM dbo.Prospect
WHERE ZipCode = @ZipCode
ORDER BY ProspectId;
SELECT ProspectId, LastName, City FROM #Batch;
GO
EXEC #Run2000;
GO
-- Cleanup.
DROP PROCEDURE #Run2000;
USE master;
ALTER DATABASE ExoTempdb SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE ExoTempdb;
GO
