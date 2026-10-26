-- Clip V6.2: the scalar functions. The list of the invoices of June 2026, slow; the reads
-- that STATISTICS IO does not show; the function called once per invoice, the serial plan;
-- is_inlineable, and what keeps this function out of the scalar UDF inlining of SQL Server
-- 2019; two rewrites measured, an inlineable scalar function and an inline table-valued
-- function. Runs on the lab, in one session, after 00-setup.sql. Creates two test functions
-- and drops them at the end: the site code stays as 00-setup.sql left it.
-- Turn on the actual plan in SSMS (Ctrl+M). Step 1 and step 6 last about 13 seconds each.
USE PachadataTraining;
GO
SET NOCOUNT ON;
GO
-- 1. The list of the invoices of June 2026: 1,029 invoices.
SET STATISTICS IO, TIME ON;
EXEC Report.InvoiceList @Start = '20260601', @End = '20260630';
SET STATISTICS IO, TIME OFF;
GO
-- 2. STATISTICS IO shows the reads of the query, not those of the function it calls.
--    sys.dm_exec_function_stats counts them: one execution per invoice.
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS FunctionName,
       execution_count,
       total_logical_reads,
       total_logical_reads / execution_count AS ReadsPerCall,
       total_worker_time / 1000 AS CpuMs
FROM sys.dm_exec_function_stats
WHERE database_id = DB_ID();
GO
-- 3. The cached plan of the list: the function appears as an operator of the plan
--    (UserDefinedFunction), and the plan stays serial.
SELECT qp.query_plan.value('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
           (//p:QueryPlan/@NonParallelPlanReason)[1]', 'varchar(60)') AS NonParallelPlanReason,
       qp.query_plan.value('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
           count(//p:UserDefinedFunction)', 'int') AS FunctionCallsInPlan
FROM sys.dm_exec_procedure_stats AS ps
CROSS APPLY sys.dm_exec_query_plan(ps.plan_handle) AS qp
WHERE ps.database_id = DB_ID() AND ps.object_id = OBJECT_ID(N'Report.InvoiceList');
GO
-- 4. The database is at level 170 and the inlining is on: so the function itself refuses it.
SELECT name, value FROM sys.database_scoped_configurations
WHERE name = N'TSQL_SCALAR_UDF_INLINING';
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS FunctionName,
       is_inlineable, inline_type
FROM sys.sql_modules
WHERE object_id = OBJECT_ID(N'Enrollment.GetInvoiceStatus');
GO
-- 5. The body of the function: it reads the invoice, sums its payments, and compares the
--    due date with GETDATE(). A time-dependent intrinsic function is one of the constructs
--    that rule out the inlining.
EXEC sys.sp_helptext N'Enrollment.GetInvoiceStatus';
GO
-- 6. A test copy that receives the date instead of reading the clock: inlineable.
CREATE OR ALTER FUNCTION Enrollment.GetInvoiceStatusAsOf (@InvoiceCode varchar(50), @AsOfDate date)
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
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS FunctionName,
       is_inlineable, inline_type
FROM sys.sql_modules
WHERE object_id = OBJECT_ID(N'Enrollment.GetInvoiceStatusAsOf');
GO
-- The query of the list with the copy, inlined; then the same query with the inlining
-- refused by a hint, to see what the inlining alone is worth. The date is that of the
-- day, computed once in the calling query.
SET STATISTICS IO, TIME ON;
SELECT i.InvoiceCode, i.InvoiceDate,
       Enrollment.GetInvoiceStatusAsOf(i.InvoiceCode, CAST(GETDATE() AS date)) AS Status
FROM Enrollment.Invoice AS i
WHERE i.InvoiceDate >= '20260601' AND i.InvoiceDate <= '20260630' AND i.DocumentType = 'I'
ORDER BY i.InvoiceDate, i.InvoiceCode;

SELECT i.InvoiceCode, i.InvoiceDate,
       Enrollment.GetInvoiceStatusAsOf(i.InvoiceCode, CAST(GETDATE() AS date)) AS Status
FROM Enrollment.Invoice AS i
WHERE i.InvoiceDate >= '20260601' AND i.InvoiceDate <= '20260630' AND i.DocumentType = 'I'
ORDER BY i.InvoiceDate, i.InvoiceCode
OPTION (USE HINT ('DISABLE_TSQL_SCALAR_UDF_INLINING'));
SET STATISTICS IO, TIME OFF;
GO
-- 7. The other rewrite: an inline table-valued function, one query, expanded into the
--    calling query by construction, whatever the version. GETDATE() is allowed in it.
CREATE OR ALTER FUNCTION Enrollment.InvoiceStatus (@InvoiceCode varchar(50))
RETURNS TABLE
AS
RETURN
    SELECT CASE WHEN p.Paid >= i.GrossAmount THEN 'PAID'
                WHEN p.Paid > 0 THEN 'PARTIAL'
                WHEN i.DueDate >= CAST(GETDATE() AS date) THEN 'PENDING'
                ELSE 'UNPAID' END AS Status
    FROM Enrollment.Invoice AS i
    CROSS APPLY (SELECT ISNULL(SUM(pa.Amount), 0) AS Paid
                 FROM Enrollment.Payment AS pa
                 WHERE pa.InvoiceCode = i.InvoiceCode) AS p
    WHERE i.InvoiceCode = @InvoiceCode;
GO
SET STATISTICS IO, TIME ON;
SELECT i.InvoiceCode, i.InvoiceDate, st.Status
FROM Enrollment.Invoice AS i
OUTER APPLY Enrollment.InvoiceStatus(i.InvoiceCode) AS st
WHERE i.InvoiceDate >= '20260601' AND i.InvoiceDate <= '20260630' AND i.DocumentType = 'I'
ORDER BY i.InvoiceDate, i.InvoiceCode;
SET STATISTICS IO, TIME OFF;
GO
-- 8. The test functions go: clip V6.4 corrects the code of the site.
DROP FUNCTION Enrollment.GetInvoiceStatusAsOf;
DROP FUNCTION Enrollment.InvoiceStatus;
GO
