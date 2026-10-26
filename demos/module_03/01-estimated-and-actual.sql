-- Clip 3.1: the estimated plan and the actual plan of the enrollees list. Runs on the lab,
-- in one session, after 00-setup.sql. In SSMS, Ctrl+L shows the estimated plan of the
-- selected statement, Ctrl+M adds the actual plan to the results; the SET commands below
-- do the same from any client and return the plan as XML.
USE PachadataTraining;
GO
-- 1. The estimated plan: compiled, not executed. No row comes back, only the plan. The
--    estimated plan of a call to sp_executesql shows the call and not the query inside,
--    so the query is written here with its value.
SET SHOWPLAN_XML ON;
GO
SELECT e.EnrollmentId, c.LastName, c.FirstName, c.Email,
       e.CreationDate, e.WaitingList
FROM Enrollment.Enrollment AS e
JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
WHERE e.SessionId = 12000
  AND e.CancellationDate IS NULL
ORDER BY c.LastName, c.FirstName;
GO
SET SHOWPLAN_XML OFF;
GO
-- 2. The actual plan: the query runs, and the plan comes back after its rows, with what
--    each operator really did. STATISTICS IO and TIME add the pages read, table by table,
--    and the time, in the Messages tab.
SET STATISTICS XML ON;
SET STATISTICS IO, TIME ON;
GO
EXEC sys.sp_executesql N'SELECT e.EnrollmentId, c.LastName, c.FirstName, c.Email,
       e.CreationDate, e.WaitingList
FROM Enrollment.Enrollment AS e
JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
WHERE e.SessionId = @SessionId
  AND e.CancellationDate IS NULL
ORDER BY c.LastName, c.FirstName;', N'@SessionId int', @SessionId = 12000;
GO
SET STATISTICS XML OFF;
SET STATISTICS IO, TIME OFF;
GO
-- 3. The plan the cache keeps is the compiled one: no actual row count in it.
SELECT qs.execution_count, qs.last_logical_reads, qs.last_rows,
       qp.query_plan.exist('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
                            //p:RunTimeInformation') AS has_actual_rows,
       qp.query_plan
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS t
CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE t.text LIKE N'(@SessionId int)%'
  AND pa.attribute = N'dbid' AND CONVERT(int, pa.value) = DB_ID();
GO
-- 4. The last actual plan of a query that has already run, without running it again:
--    LAST_QUERY_PLAN_STATS, a database scoped configuration (SQL Server 2019 and later),
--    off by default. It costs a little on every query of the database while it is on.
ALTER DATABASE SCOPED CONFIGURATION SET LAST_QUERY_PLAN_STATS = ON;
GO
EXEC sys.sp_executesql N'SELECT e.EnrollmentId, c.LastName, c.FirstName, c.Email,
       e.CreationDate, e.WaitingList
FROM Enrollment.Enrollment AS e
JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
WHERE e.SessionId = @SessionId
  AND e.CancellationDate IS NULL
ORDER BY c.LastName, c.FirstName;', N'@SessionId int', @SessionId = 12000;
GO
SELECT qs.execution_count,
       ps.query_plan.exist('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
                            //p:RunTimeInformation') AS has_actual_rows,
       ps.query_plan
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS t
CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
CROSS APPLY sys.dm_exec_query_plan_stats(qs.plan_handle) AS ps
WHERE t.text LIKE N'(@SessionId int)%'
  AND pa.attribute = N'dbid' AND CONVERT(int, pa.value) = DB_ID();
GO
ALTER DATABASE SCOPED CONFIGURATION SET LAST_QUERY_PLAN_STATS = OFF;
GO
