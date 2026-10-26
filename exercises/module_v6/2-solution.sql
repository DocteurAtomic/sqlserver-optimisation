-- Exercise of module V6, solution. Runs on the lab, in one session, after 1-start.sql.
-- Measures the two pieces of code of 1-start.sql, rewrites each one, checks that the result
-- has not changed and measures again. At the end, drops what 1-start.sql created.
USE PachadataTraining;
GO
SET NOCOUNT ON;
GO
-- Part 1. The cash of 2025, loop and cursor.
-- 1. The procedure as delivered. Its result is kept for the comparison of step 3.
EXEC sys.sp_recompile N'Enrollment.CashRunningTotal';
GO
CREATE TABLE #CashBefore (PaymentDay date PRIMARY KEY, Amount decimal(19, 2), RunningTotal decimal(19, 2));
INSERT #CashBefore EXEC Enrollment.CashRunningTotal @Year = 2025;
SELECT last_logical_reads, last_worker_time / 1000 AS LastCpuMs
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Enrollment.CashRunningTotal');
GO
-- 2. Where it goes: the SELECT of the loop runs once per day, 365 times, and scans
--    Enrollment.Payment each time (no index on PaymentDate).
SELECT TOP (3) qs.execution_count, qs.total_logical_reads, qs.total_worker_time / 1000 AS CpuMs,
       LEFT(LTRIM(REPLACE(REPLACE(SUBSTRING(st.text, qs.statement_start_offset / 2 + 1, 120),
            CHAR(13), ' '), CHAR(10), ' ')), 50) AS StatementText
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
WHERE st.dbid = DB_ID() AND st.objectid = OBJECT_ID(N'Enrollment.CashRunningTotal')
ORDER BY qs.total_logical_reads DESC;
GO
-- 3. The rewrite: GENERATE_SERIES (SQL Server 2022, level 160) gives the days of the year in
--    one statement; the payments are read once and grouped by day; the running total is a
--    window, framed by ROWS. Same name, same parameter, same result.
CREATE OR ALTER PROCEDURE Enrollment.CashRunningTotal
    @Year int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @First date = DATEFROMPARTS(@Year, 1, 1);
    WITH Days AS (
        SELECT DATEADD(day, g.value, @First) AS PaymentDay
        FROM GENERATE_SERIES(0, DATEDIFF(day, @First, DATEFROMPARTS(@Year, 12, 31))) AS g
    ),
    Cash AS (
        SELECT PaymentDate, SUM(Amount) AS Amount
        FROM Enrollment.Payment
        WHERE PaymentDate >= @First AND PaymentDate < DATEADD(year, 1, @First)
        GROUP BY PaymentDate
    )
    SELECT d.PaymentDay,
           CAST(ISNULL(c.Amount, 0) AS decimal(19, 2)) AS Amount,
           CAST(SUM(ISNULL(c.Amount, 0)) OVER (ORDER BY d.PaymentDay ROWS UNBOUNDED PRECEDING)
                AS decimal(19, 2)) AS RunningTotal
    FROM Days AS d
    LEFT JOIN Cash AS c ON c.PaymentDate = d.PaymentDay
    ORDER BY d.PaymentDay;
END;
GO
CREATE TABLE #CashAfter (PaymentDay date PRIMARY KEY, Amount decimal(19, 2), RunningTotal decimal(19, 2));
INSERT #CashAfter EXEC Enrollment.CashRunningTotal @Year = 2025;
SELECT last_logical_reads, last_worker_time / 1000 AS LastCpuMs
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Enrollment.CashRunningTotal');
SELECT COUNT(*) AS DaysThatDiffer
FROM (SELECT * FROM #CashBefore EXCEPT SELECT * FROM #CashAfter) AS x;
DROP TABLE #CashBefore, #CashAfter;
GO
-- Part 2. The fill status of the sessions.
-- 4. The function is not inlineable, while the database allows it.
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS FunctionName,
       is_inlineable, inline_type
FROM sys.sql_modules
WHERE object_id = OBJECT_ID(N'Course.GetFillStatus');
GO
-- 5. The list as delivered, measured; the function runs once per session.
EXEC sys.sp_recompile N'Course.SessionList';
GO
CREATE TABLE #ListBefore (SessionId int PRIMARY KEY, CourseId int, StartDate date,
                          StatusCode char(10), FillStatus varchar(12));
INSERT #ListBefore EXEC Course.SessionList @Start = '20110101', @End = '20271231';
SELECT last_logical_reads, last_worker_time / 1000 AS LastCpuMs
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Course.SessionList');
SELECT execution_count, total_logical_reads, total_worker_time / 1000 AS CpuMs
FROM sys.dm_exec_function_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Course.GetFillStatus');
GO
-- 6. The cause: since SQL Server 2019 CU5, a function with more than one RETURN is not
--    inlined. The rewrite keeps the name, the signature and the rules, with a single RETURN.
--    DECLARE, SET, SELECT and IF ... ELSE are allowed; the early exit is not.
CREATE OR ALTER FUNCTION Course.GetFillStatus (@SessionId int)
RETURNS varchar(12)
AS
BEGIN
    DECLARE @Seats int, @Enrolled int, @Status varchar(12);
    SELECT @Seats = r.Seats
    FROM Course.Session AS s
    JOIN Reference.TrainingRoom AS r ON r.TrainingRoomId = s.TrainingRoomId
    WHERE s.SessionId = @SessionId;
    SELECT @Enrolled = COUNT(*)
    FROM Enrollment.Enrollment
    WHERE SessionId = @SessionId AND WaitingList = 0 AND CancellationDate IS NULL;
    IF @Seats IS NULL SET @Status = 'NO ROOM';
    ELSE IF @Enrolled >= @Seats SET @Status = 'FULL';
    ELSE IF @Enrolled >= @Seats * 0.8 SET @Status = 'ALMOST FULL';
    ELSE SET @Status = 'OPEN';
    RETURN @Status;
END;
GO
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS FunctionName,
       is_inlineable, inline_type
FROM sys.sql_modules
WHERE object_id = OBJECT_ID(N'Course.GetFillStatus');
GO
-- 7. The same list, the function now inlined: compiled again since the function changed.
EXEC sys.sp_recompile N'Course.SessionList';
GO
CREATE TABLE #ListAfter (SessionId int PRIMARY KEY, CourseId int, StartDate date,
                         StatusCode char(10), FillStatus varchar(12));
INSERT #ListAfter EXEC Course.SessionList @Start = '20110101', @End = '20271231';
SELECT last_logical_reads, last_worker_time / 1000 AS LastCpuMs
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Course.SessionList');
SELECT COUNT(*) AS SessionsThatDiffer
FROM (SELECT * FROM #ListBefore EXCEPT SELECT * FROM #ListAfter) AS x;
GO
-- 8. Inlined, the function still counts the enrollments of each session: the plan builds an
--    Index Spool on Enrollment.Enrollment and seeks in it 19,300 times, and the IF ... ELSE
--    become a cascade of nested loops. The list written without function counts all the
--    enrollments once, in one aggregate, and joins it.
CREATE OR ALTER PROCEDURE Course.SessionList
    @Start date,
    @End   date
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.SessionId, s.CourseId, s.StartDate, s.StatusCode,
           CAST(CASE WHEN r.Seats IS NULL THEN 'NO ROOM'
                     WHEN ISNULL(e.Enrolled, 0) >= r.Seats THEN 'FULL'
                     WHEN ISNULL(e.Enrolled, 0) >= r.Seats * 0.8 THEN 'ALMOST FULL'
                     ELSE 'OPEN' END AS varchar(12)) AS FillStatus
    FROM Course.Session AS s
    LEFT JOIN Reference.TrainingRoom AS r ON r.TrainingRoomId = s.TrainingRoomId
    LEFT JOIN (SELECT SessionId, COUNT(*) AS Enrolled
               FROM Enrollment.Enrollment
               WHERE WaitingList = 0 AND CancellationDate IS NULL
               GROUP BY SessionId) AS e ON e.SessionId = s.SessionId
    WHERE s.StartDate >= @Start AND s.StartDate <= @End
    ORDER BY s.StartDate, s.SessionId;
END;
GO
CREATE TABLE #ListSet (SessionId int PRIMARY KEY, CourseId int, StartDate date,
                       StatusCode char(10), FillStatus varchar(12));
INSERT #ListSet EXEC Course.SessionList @Start = '20110101', @End = '20271231';
SELECT last_logical_reads, last_worker_time / 1000 AS LastCpuMs
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Course.SessionList');
SELECT COUNT(*) AS SessionsThatDiffer
FROM (SELECT * FROM #ListBefore EXCEPT SELECT * FROM #ListSet) AS x;
DROP TABLE #ListBefore, #ListAfter, #ListSet;
GO
-- Cleanup: the objects created by 1-start.sql.
DROP PROCEDURE Enrollment.CashRunningTotal, Course.SessionList;
DROP FUNCTION Course.GetFillStatus;
GO
