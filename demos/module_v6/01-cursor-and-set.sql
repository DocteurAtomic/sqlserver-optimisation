-- Clip V6.1: the cursor and the set. The complaint of the accounting team, the report of the
-- revenue per course measured, where its reads go, the pair Demo.RevenueByCourse_Slow and
-- _Fixed, then the window functions that compute the share and the running total in the
-- same query. Runs on the lab, in one session, after 00-setup.sql. Changes nothing.
-- SET STATISTICS IO and TIME stay off around the cursors: they write one message per FETCH,
-- 110,000 of them, and SSMS spends minutes printing them. The reads and the CPU are read in
-- sys.dm_exec_procedure_stats instead.
USE PachadataTraining;
GO
SET NOCOUNT ON;
GO
-- 1. The report of the accounting team: 506 courses, one row each.
EXEC Report.RevenueByCourse;
GO
-- 2. What the cache knows of the call: reads and CPU per execution.
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS ProcedureName,
       execution_count,
       total_logical_reads / execution_count AS ReadsPerCall,
       total_worker_time / execution_count / 1000 AS CpuMsPerCall
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Report.RevenueByCourse');
GO
-- 3. Where the reads go: the statements of the procedure, the most expensive first. FETCH
--    runs once per billing document. The SET and IF of the loop run as many times, and do
--    not appear in this view.
SELECT TOP (3) qs.execution_count,
       qs.total_logical_reads,
       qs.total_worker_time / 1000 AS CpuMs,
       LEFT(LTRIM(REPLACE(REPLACE(SUBSTRING(st.text, qs.statement_start_offset / 2 + 1,
            CASE qs.statement_end_offset WHEN -1 THEN 200
                 ELSE (qs.statement_end_offset - qs.statement_start_offset) / 2 + 1 END),
            CHAR(13), ' '), CHAR(10), ' ')), 50) AS StatementText
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE st.dbid = DB_ID() AND st.objectid = OBJECT_ID(N'Report.RevenueByCourse')
ORDER BY qs.total_logical_reads DESC;
SELECT COUNT(*) AS BillingDocuments
FROM Enrollment.Invoice AS i
JOIN Course.Session AS s ON s.SessionId = i.SessionId;
GO
-- 4. The pair of the database: the same cursor, and the GROUP BY that replaces it.
EXEC Demo.RevenueByCourse_Slow;
EXEC Demo.RevenueByCourse_Fixed;
GO
SELECT OBJECT_NAME(object_id) AS ProcedureName,
       execution_count,
       total_logical_reads / execution_count AS ReadsPerCall,
       total_worker_time / execution_count / 1000 AS CpuMsPerCall
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID()
  AND object_id IN (OBJECT_ID(N'Demo.RevenueByCourse_Slow'), OBJECT_ID(N'Demo.RevenueByCourse_Fixed'));
GO
-- 5. The share of each course needs the total of all the courses. A window function over
--    the aggregate gives it in the same query: SUM(SUM(...)) OVER (). The running share,
--    courses sorted by revenue, is a framed window: ROWS UNBOUNDED PRECEDING, written out,
--    since the default frame is RANGE.
SET STATISTICS IO, TIME ON;
SELECT s.CourseId,
       SUM(i.NetAmount) AS NetRevenue,
       COUNT(*) AS DocumentCount,
       CAST(100 * SUM(i.NetAmount) / SUM(SUM(i.NetAmount)) OVER () AS decimal(5, 2)) AS SharePct,
       CAST(100 * SUM(SUM(i.NetAmount)) OVER (ORDER BY SUM(i.NetAmount) DESC, s.CourseId
                                              ROWS UNBOUNDED PRECEDING)
                / SUM(SUM(i.NetAmount)) OVER () AS decimal(5, 2)) AS RunningSharePct
FROM Enrollment.Invoice AS i
JOIN Course.Session AS s ON s.SessionId = i.SessionId
GROUP BY s.CourseId
ORDER BY NetRevenue DESC, s.CourseId;
SET STATISTICS IO, TIME OFF;
GO
-- 6. How many courses make 80 % of the revenue: the running share answers it.
WITH Revenue AS (
    SELECT s.CourseId,
           SUM(SUM(i.NetAmount)) OVER (ORDER BY SUM(i.NetAmount) DESC, s.CourseId
                                       ROWS UNBOUNDED PRECEDING)
             / SUM(SUM(i.NetAmount)) OVER () AS RunningShare
    FROM Enrollment.Invoice AS i
    JOIN Course.Session AS s ON s.SessionId = i.SessionId
    GROUP BY s.CourseId
)
SELECT COUNT(*) AS CoursesFor80Pct, (SELECT COUNT(*) FROM Revenue) AS Courses
FROM Revenue
WHERE RunningShare <= 0.80;
GO
