-- Clip V1.2: implicit conversions. An nvarchar parameter on a varchar column, under the
-- Windows collation of the database, then under a SQL collation. Runs on the lab, in one
-- session, after 00-setup.sql. Reads only. Turn on the actual plan in SSMS (Ctrl+M).
USE PachadataTraining;
GO
-- The two collations: the database, and the copy of the prospects.
SELECT DATABASEPROPERTYEX(DB_NAME(), 'Collation') AS DatabaseCollation;

SELECT OBJECT_NAME(c.object_id) AS TableName, c.name AS ColumnName, t.name AS TypeName,
       c.max_length, c.collation_name
FROM sys.columns AS c
JOIN sys.types AS t ON t.user_type_id = c.user_type_id
WHERE c.object_id IN (OBJECT_ID(N'Contact.Contact'), OBJECT_ID(N'Contact.ProspectUS_SQL_Latin1'))
  AND c.name = N'LastName';
GO
-- The pages of Contact.Contact read once, so that the measures below compare warm reads.
SELECT COUNT(*) AS Contacts, MAX(Email) AS LastEmail FROM Contact.Contact;
SELECT COUNT(DISTINCT LastName) AS LastNames FROM Contact.Contact;
GO
SET STATISTICS IO, TIME ON;
GO
-- 1. Windows collation (French_CI_AS): the pair of the database, nvarchar then varchar.
EXEC Demo.ContactsByName_Slow @LastName = N'Jones';
EXEC Demo.ContactsByName_Fixed @LastName = 'Jones';
GO
-- 2. SQL collation: the prospect search of the sales team, its parameter in nvarchar.
EXEC Contact.FindProspectsByName @LastName = N'Kowalski';
GO
-- 3. The same query, the parameter declared with the type of the column, as the
--    application would send it.
EXEC sys.sp_executesql
    N'SELECT FirstName, LastName, City FROM Contact.ProspectUS_SQL_Latin1 WHERE LastName = @LastName;',
    N'@LastName varchar(50)', @LastName = 'Kowalski';
GO
SET STATISTICS IO, TIME OFF;
GO
-- 4. The plans of this database that convert a column in a way that prevents a seek,
--    found in the cache: the PlanAffectingConvert warning with ConvertIssue "Seek Plan".
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT OBJECT_SCHEMA_NAME(st.objectid, st.dbid) + '.' + OBJECT_NAME(st.objectid, st.dbid) AS ObjectName,
       qs.execution_count,
       qs.total_logical_reads / qs.execution_count AS avg_logical_reads,
       w.c.value('@Expression', 'nvarchar(200)') AS Conversion
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
CROSS APPLY qp.query_plan.nodes('//Warnings/PlanAffectingConvert') AS w(c)
WHERE w.c.value('@ConvertIssue', 'varchar(30)') = 'Seek Plan'
  AND st.dbid = DB_ID();
GO
