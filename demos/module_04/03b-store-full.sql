-- Clip 4.3: the store that fills up and switches to read-only without warning. Runs on the
-- lab, in one session. It changes the Query Store settings of the lab database only, and
-- puts them back at the end (200 MB, size-based cleanup, READ_WRITE).
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- The size limit lowered to 3 MB, the size-based cleanup turned off: what a store sized for
-- a well-parameterized application gets from one that concatenates its values.
ALTER DATABASE CURRENT SET QUERY_STORE (MAX_STORAGE_SIZE_MB = 3, SIZE_BASED_CLEANUP_MODE = OFF);
SELECT actual_state_desc, readonly_reason, current_storage_size_mb, max_storage_size_mb
FROM sys.database_query_store_options;
GO
-- 3,000 distinct queries, as an application that writes its values into the SQL text
-- produces them. Each one is a new query for Query Store. Their results go to a temporary
-- table, not to the screen.
CREATE TABLE #Ids (ContactId int);
DECLARE @i int = 1, @sql nvarchar(max);
WHILE @i <= 3000
BEGIN
    SET @sql = N'SELECT TOP (1) c.ContactId AS c' + CAST(@i AS nvarchar(10))
             + N' FROM Contact.Contact AS c JOIN Contact.Company AS co ON co.CompanyId = c.CompanyId'
             + N' ORDER BY c.ContactId;';
    INSERT #Ids EXEC (@sql);
    SET @i += 1;
END;
DROP TABLE #Ids;
GO
-- The size is checked only when Query Store writes to disk, every DATA_FLUSH_INTERVAL_SECONDS
-- (900 by default). sp_query_store_flush_db writes now.
SELECT actual_state_desc, readonly_reason, current_storage_size_mb, max_storage_size_mb
FROM sys.database_query_store_options;
EXEC sys.sp_query_store_flush_db;
SELECT actual_state_desc, desired_state_desc, readonly_reason,
       current_storage_size_mb, max_storage_size_mb
FROM sys.database_query_store_options;
GO
-- Read-only: the views still answer, but a new query is no longer captured.
SELECT COUNT(*) AS ContactsArsac FROM Contact.Contact WHERE LastName = 'Arsac' OPTION (MAXDOP 1);
WAITFOR DELAY '00:00:02';  -- a new query can take a second or two to show
SELECT COUNT(*) AS captured
FROM sys.query_store_query_text
WHERE query_sql_text LIKE N'%ContactsArsac%' AND query_sql_text NOT LIKE N'%query[_]store%';
GO
-- The watch query: the state, the reason and the fill ratio. Above 80 %, act.
SELECT actual_state_desc, readonly_reason, current_storage_size_mb, max_storage_size_mb,
       CAST(current_storage_size_mb * 100.0 / NULLIF(max_storage_size_mb, 0) AS decimal(6, 1)) AS pct_used
FROM sys.database_query_store_options;
GO
-- The way back: a larger limit, the cleanup turned on again, and READ_WRITE asked again.
ALTER DATABASE CURRENT SET QUERY_STORE (MAX_STORAGE_SIZE_MB = 200, SIZE_BASED_CLEANUP_MODE = AUTO);
SELECT actual_state_desc, readonly_reason FROM sys.database_query_store_options;
ALTER DATABASE CURRENT SET QUERY_STORE (OPERATION_MODE = READ_WRITE);
SELECT actual_state_desc, readonly_reason, current_storage_size_mb, max_storage_size_mb
FROM sys.database_query_store_options;
