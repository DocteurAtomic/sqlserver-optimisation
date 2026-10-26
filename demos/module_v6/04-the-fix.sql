-- Clip V6.4, the end of the module: what 00-setup.sql did, how to find the same code in a
-- database, the two reports rewritten and measured. Runs on the lab, in one session, after
-- 03-temp-tables.sql. Changes Report.RevenueByCourse, Enrollment.GetInvoiceStatus and
-- Report.InvoiceList; the 00-setup.sql of the next module restores the database.
-- Step 1 lasts about 13 seconds.
USE PachadataTraining;
GO
SET NOCOUNT ON;
GO
-- 1. Before: the two reports as 00-setup.sql left them. Their results are kept in two
--    temporary tables, to compare them with those of the rewritten reports.
EXEC sys.sp_recompile N'Report.RevenueByCourse';
EXEC sys.sp_recompile N'Report.InvoiceList';
GO
CREATE TABLE #RevenueBefore (CourseId int PRIMARY KEY, NetRevenue decimal(19, 2),
                             DocumentCount int, SharePct decimal(5, 2));
INSERT #RevenueBefore EXEC Report.RevenueByCourse;
CREATE TABLE #InvoicesBefore (InvoiceCode varchar(50) PRIMARY KEY, InvoiceDate date, DueDate date,
                              Customer varchar(200), GrossAmount decimal(9, 2), Status varchar(10));
INSERT #InvoicesBefore EXEC Report.InvoiceList @Start = '20260601', @End = '20260630';
GO
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS ProcedureName,
       last_logical_reads, last_worker_time / 1000 AS LastCpuMs
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID()
  AND object_id IN (OBJECT_ID(N'Report.RevenueByCourse'), OBJECT_ID(N'Report.InvoiceList'))
ORDER BY ProcedureName;
GO
-- 2. The same code elsewhere: the modules that declare a cursor, and the scalar functions
--    that the engine cannot inline.
SELECT OBJECT_SCHEMA_NAME(m.object_id) + N'.' + OBJECT_NAME(m.object_id) AS ModuleName,
       o.type_desc
FROM sys.sql_modules AS m
JOIN sys.objects AS o ON o.object_id = m.object_id
WHERE m.definition LIKE N'%DECLARE%CURSOR%'
   OR (o.type = 'FN' AND m.is_inlineable = 0)
ORDER BY o.type_desc, ModuleName;
GO
-- 3. The first fix: the revenue per course in one query. The share comes from a window
--    over the aggregate.
CREATE OR ALTER PROCEDURE Report.RevenueByCourse
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.CourseId,
           CAST(SUM(i.NetAmount) AS decimal(19, 2)) AS NetRevenue,
           COUNT(*) AS DocumentCount,
           CAST(100 * SUM(i.NetAmount) / NULLIF(SUM(SUM(i.NetAmount)) OVER (), 0) AS decimal(5, 2)) AS SharePct
    FROM Enrollment.Invoice AS i
    JOIN Course.Session AS s ON s.SessionId = i.SessionId
    GROUP BY s.CourseId
    ORDER BY s.CourseId;
END;
GO
-- 4. The second fix: the function receives the date instead of reading the clock, and the
--    report passes it, the date of the day by default. The function becomes inlineable.
CREATE OR ALTER FUNCTION Enrollment.GetInvoiceStatus (@InvoiceCode varchar(50), @AsOfDate date)
RETURNS varchar(10)
AS
BEGIN
    DECLARE @Gross decimal(9, 2), @Due date, @Paid decimal(9, 2), @Status varchar(10);
    SELECT @Gross = GrossAmount, @Due = DueDate
    FROM Enrollment.Invoice
    WHERE InvoiceCode = @InvoiceCode;
    SELECT @Paid = ISNULL(SUM(Amount), 0)
    FROM Enrollment.Payment
    WHERE InvoiceCode = @InvoiceCode;
    IF @Paid >= @Gross SET @Status = 'PAID';
    ELSE IF @Paid > 0 SET @Status = 'PARTIAL';
    ELSE IF @Due >= @AsOfDate SET @Status = 'PENDING';
    ELSE SET @Status = 'UNPAID';
    RETURN @Status;
END;
GO
CREATE OR ALTER PROCEDURE Report.InvoiceList
    @Start    date,
    @End      date,
    @AsOfDate date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @AsOfDate = ISNULL(@AsOfDate, CAST(GETDATE() AS date));
    SELECT i.InvoiceCode, i.InvoiceDate, i.DueDate,
           COALESCE(co.Name, c.LastName + ISNULL(' ' + c.FirstName, '')) AS Customer,
           i.GrossAmount,
           Enrollment.GetInvoiceStatus(i.InvoiceCode, @AsOfDate) AS Status
    FROM Enrollment.Invoice AS i
    LEFT JOIN Contact.Company AS co ON co.CompanyId = i.CompanyId
    LEFT JOIN Contact.Contact AS c ON c.ContactId = i.ContactId
    WHERE i.InvoiceDate >= @Start AND i.InvoiceDate <= @End
      AND i.DocumentType = 'I'
    ORDER BY i.InvoiceDate, i.InvoiceCode;
END;
GO
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS FunctionName,
       is_inlineable, inline_type
FROM sys.sql_modules
WHERE object_id = OBJECT_ID(N'Enrollment.GetInvoiceStatus');
GO
-- 5. After: the same calls, and the results compared with those of before.
CREATE TABLE #RevenueAfter (CourseId int PRIMARY KEY, NetRevenue decimal(19, 2),
                            DocumentCount int, SharePct decimal(5, 2));
INSERT #RevenueAfter EXEC Report.RevenueByCourse;
CREATE TABLE #InvoicesAfter (InvoiceCode varchar(50) PRIMARY KEY, InvoiceDate date, DueDate date,
                             Customer varchar(200), GrossAmount decimal(9, 2), Status varchar(10));
INSERT #InvoicesAfter EXEC Report.InvoiceList @Start = '20260601', @End = '20260630';
GO
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS ProcedureName,
       last_logical_reads, last_worker_time / 1000 AS LastCpuMs
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID()
  AND object_id IN (OBJECT_ID(N'Report.RevenueByCourse'), OBJECT_ID(N'Report.InvoiceList'))
ORDER BY ProcedureName;
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS FunctionName,
       execution_count
FROM sys.dm_exec_function_stats
WHERE database_id = DB_ID();

SELECT (SELECT COUNT(*) FROM (SELECT * FROM #RevenueBefore EXCEPT SELECT * FROM #RevenueAfter) AS x)
           AS RevenueRowsThatDiffer,
       (SELECT COUNT(*) FROM (SELECT * FROM #InvoicesBefore EXCEPT SELECT * FROM #InvoicesAfter) AS x)
           AS InvoiceRowsThatDiffer;
GO
-- 6. The plan of the list, once again: no function operator any more, and a parallel plan.
SELECT qp.query_plan.value('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
           (//p:QueryPlan/@NonParallelPlanReason)[1]', 'varchar(60)') AS NonParallelPlanReason,
       qp.query_plan.value('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
           count(//p:UserDefinedFunction)', 'int') AS FunctionCallsInPlan,
       qp.query_plan.value('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
           count(//p:RelOp[@PhysicalOp="Parallelism"])', 'int') AS ParallelismOperators
FROM sys.dm_exec_procedure_stats AS ps
CROSS APPLY sys.dm_exec_query_plan(ps.plan_handle) AS qp
WHERE ps.database_id = DB_ID() AND ps.object_id = OBJECT_ID(N'Report.InvoiceList');
GO
