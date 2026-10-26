-- Clip V6.3: temporary tables and table variables. The same filter on a table variable and
-- on a temporary table: the number of rows is known, the distribution is not, and the
-- estimate becomes a guess; then the recompilation, that a temporary table triggers when
-- its content changes and a table variable does not. Runs on the lab, in one session, after
-- 00-setup.sql. Creates two procedures in the Marketing schema and drops them at the end.
-- Turn on the actual plan in SSMS (Ctrl+M).
USE PachadataTraining;
GO
SET NOCOUNT ON;
GO
-- 1. The contacts and their company, in a table variable, then the deliveries received by
--    the contacts of the largest client company (3,218 contacts).
DECLARE @Contacts TABLE (ContactId int NOT NULL PRIMARY KEY, CompanyId int NULL);
INSERT @Contacts (ContactId, CompanyId)
SELECT ContactId, CompanyId FROM Contact.Contact;

SET STATISTICS IO, TIME ON;
SELECT COUNT(*) AS Deliveries, SUM(CAST(d.Opened AS int)) AS Opened
FROM @Contacts AS t
JOIN Marketing.Delivery AS d ON d.ContactId = t.ContactId
WHERE t.CompanyId = 1050;
SET STATISTICS IO, TIME OFF;
GO
-- 2. The same rows and the same query on a temporary table.
CREATE TABLE #Contacts (ContactId int NOT NULL PRIMARY KEY, CompanyId int NULL);
INSERT #Contacts (ContactId, CompanyId)
SELECT ContactId, CompanyId FROM Contact.Contact;

SET STATISTICS IO, TIME ON;
SELECT COUNT(*) AS Deliveries, SUM(CAST(d.Opened AS int)) AS Opened
FROM #Contacts AS t
JOIN Marketing.Delivery AS d ON d.ContactId = t.ContactId
WHERE t.CompanyId = 1050;
SET STATISTICS IO, TIME OFF;
GO
-- 3. What the optimizer had for the temporary table: a statistic created on CompanyId by
--    the query itself (_WA_Sys_...), with its histogram. A table variable never has one.
SELECT s.name AS StatisticName, s.auto_created, sp.rows, sp.steps
FROM tempdb.sys.stats AS s
JOIN tempdb.sys.stats_columns AS sc ON sc.object_id = s.object_id AND sc.stats_id = s.stats_id
JOIN tempdb.sys.columns AS c ON c.object_id = sc.object_id AND c.column_id = sc.column_id
CROSS APPLY tempdb.sys.dm_db_stats_properties(s.object_id, s.stats_id) AS sp
WHERE s.object_id = OBJECT_ID(N'tempdb..#Contacts') AND c.name = N'CompanyId';
DROP TABLE #Contacts;
GO
-- 4. The recompilation. Two versions of the same procedure: the deliveries received by the
--    contacts of one company, kept first in a table variable, or in a temporary table.
CREATE OR ALTER PROCEDURE Marketing.CompanyReach_TableVariable @CompanyId int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Contacts TABLE (ContactId int NOT NULL PRIMARY KEY);
    INSERT @Contacts (ContactId)
    SELECT ContactId FROM Contact.Contact WHERE CompanyId = @CompanyId;
    SELECT COUNT(*) AS Deliveries, SUM(CAST(d.Opened AS int)) AS Opened
    FROM @Contacts AS t
    JOIN Marketing.Delivery AS d ON d.ContactId = t.ContactId;
END;
GO
CREATE OR ALTER PROCEDURE Marketing.CompanyReach_TempTable @CompanyId int
AS
BEGIN
    SET NOCOUNT ON;
    CREATE TABLE #Contacts (ContactId int NOT NULL PRIMARY KEY);
    INSERT #Contacts (ContactId)
    SELECT ContactId FROM Contact.Contact WHERE CompanyId = @CompanyId;
    SELECT COUNT(*) AS Deliveries, SUM(CAST(d.Opened AS int)) AS Opened
    FROM #Contacts AS t
    JOIN Marketing.Delivery AS d ON d.ContactId = t.ContactId;
END;
GO
-- Each one called first for a company of four contacts (196), then for the largest (1050).
SET STATISTICS IO ON;
EXEC Marketing.CompanyReach_TableVariable @CompanyId = 196;
EXEC Marketing.CompanyReach_TableVariable @CompanyId = 1050;
EXEC Marketing.CompanyReach_TempTable @CompanyId = 196;
EXEC Marketing.CompanyReach_TempTable @CompanyId = 1050;
SET STATISTICS IO OFF;
GO
-- 5. The cache: the SELECT of the table variable version ran twice on the same plan; that
--    of the temporary table was recompiled before the second call, and its plan has run once.
SELECT OBJECT_NAME(st.objectid) AS ProcedureName,
       qs.execution_count,
       qs.min_logical_reads,
       qs.last_logical_reads
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE st.dbid = DB_ID()
  AND st.objectid IN (OBJECT_ID(N'Marketing.CompanyReach_TableVariable'),
                      OBJECT_ID(N'Marketing.CompanyReach_TempTable'))
  AND SUBSTRING(st.text, qs.statement_start_offset / 2 + 1, 20) LIKE N'SELECT COUNT%'
ORDER BY ProcedureName;
GO
-- 6. A table variable is not part of the transaction: the rollback leaves its rows.
DECLARE @Log TABLE (Message varchar(100));
CREATE TABLE #Log (Message varchar(100));
BEGIN TRANSACTION;
INSERT @Log VALUES ('invoice run started');
INSERT #Log VALUES ('invoice run started');
ROLLBACK;
SELECT (SELECT COUNT(*) FROM @Log) AS RowsInTableVariable,
       (SELECT COUNT(*) FROM #Log) AS RowsInTempTable;
DROP TABLE #Log;
GO
DROP PROCEDURE Marketing.CompanyReach_TableVariable, Marketing.CompanyReach_TempTable;
GO
