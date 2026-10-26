-- Clip V1.3: data types. The same million prospects stored three times, in varchar,
-- nvarchar and varchar(max): pages, row size, reads, and the memory a sort asks for.
-- Runs on the lab, in one session. Reads only, apart from the procedure cache of this
-- database, emptied at the start so that the sorts compile.
USE PachadataTraining;
GO
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
-- 1. The declared types of LastName and Email in the three tables.
SELECT OBJECT_NAME(c.object_id) AS TableName, c.name AS ColumnName, t.name AS TypeName,
       c.max_length
FROM sys.columns AS c
JOIN sys.types AS t ON t.user_type_id = c.user_type_id
WHERE c.object_id IN (OBJECT_ID(N'Contact.ProspectUS'), OBJECT_ID(N'Contact.ProspectUS_N'),
                      OBJECT_ID(N'Contact.ProspectUS_MAX'))
  AND c.name IN (N'LastName', N'Email')
ORDER BY TableName, ColumnName;
GO
-- 2. What the columns really hold: lengths in characters.
SELECT MAX(LEN(LastName)) AS MaxLastName, MAX(LEN(Email)) AS MaxEmail,
       AVG(LEN(Email)) AS AvgEmail
FROM Contact.ProspectUS;
GO
-- 3. Pages and average row size of the three heaps.
SELECT OBJECT_NAME(ps.object_id) AS TableName, ps.page_count, ps.record_count,
       ps.avg_record_size_in_bytes
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED') AS ps
WHERE ps.object_id IN (OBJECT_ID(N'Contact.ProspectUS'), OBJECT_ID(N'Contact.ProspectUS_N'),
                       OBJECT_ID(N'Contact.ProspectUS_MAX'))
  AND ps.index_id = 0 AND ps.alloc_unit_type_desc = N'IN_ROW_DATA'
ORDER BY ps.page_count;
GO
-- 4. One scan of each table: the pages read follow the size.
SET STATISTICS IO ON;
SELECT COUNT(*) AS Prospects FROM Contact.ProspectUS WHERE Email LIKE '%@gmail.com';
SELECT COUNT(*) AS Prospects FROM Contact.ProspectUS_N WHERE Email LIKE N'%@gmail.com';
SET STATISTICS IO OFF;
GO
-- 5. The same sort of the 20,342 prospects of Arlington, in varchar and in varchar(max).
--    The rows go to variables, so that SSMS does not display them.
DECLARE @FirstName varchar(50), @LastName varchar(50), @Email varchar(100);
SELECT @FirstName = FirstName, @LastName = LastName, @Email = Email
FROM Contact.ProspectUS
WHERE City = 'Arlington'
ORDER BY LastName, FirstName;
GO
DECLARE @FirstName varchar(max), @LastName varchar(max), @Email varchar(max);
SELECT @FirstName = FirstName, @LastName = LastName, @Email = Email
FROM Contact.ProspectUS_MAX
WHERE City = 'Arlington'
ORDER BY LastName, FirstName;
GO
-- The memory granted to each sort and the memory used, in KB, with the CPU time in ms.
SELECT CASE WHEN st.text LIKE N'%ProspectUS_MAX%' THEN 'varchar(max)' ELSE 'varchar(50)' END AS Types,
       qs.last_grant_kb, qs.last_used_grant_kb, qs.last_logical_reads,
       qs.last_worker_time / 1000 AS last_cpu_ms
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
WHERE st.text LIKE N'%City = ''Arlington''%ORDER BY LastName, FirstName%'
  AND st.text NOT LIKE N'%dm_exec_query_stats%'
  AND pa.attribute = N'dbid' AND CONVERT(int, pa.value) = DB_ID();
GO
-- 6. Dates: the bytes of the same day in four types.
DECLARE @d datetime2(7) = '2026-10-18';
SELECT DATALENGTH(CAST(@d AS date)) AS [date],
       DATALENGTH(CAST(@d AS smalldatetime)) AS [smalldatetime],
       DATALENGTH(CAST(@d AS datetime)) AS [datetime],
       DATALENGTH(@d) AS [datetime2(7)];
GO
