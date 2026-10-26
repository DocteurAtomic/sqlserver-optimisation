-- Module V6, setup. Runs on the lab, in one session, before the first clip of the module.
-- It lasts a few seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. The problem of the module, two pieces of the accounting code of the site:
--    a. Report.RevenueByCourse, the net revenue per course and its share of the total, is
--       written with a cursor: one FETCH per billing document, about 110,000 of them, where
--       one GROUP BY reads the table once. Same logic as Demo.RevenueByCourse_Slow, plus
--       the share of each course.
--    b. Report.InvoiceList, the list of the invoices of a period with their status, calls
--       the scalar function Enrollment.GetInvoiceStatus once per invoice. The function
--       reads the invoice and its payments (Enrollment.Payment has no index on
--       InvoiceCode: one scan per call), and compares the due date with GETDATE(). A
--       time-dependent function makes it ineligible for the scalar UDF inlining of
--       SQL Server 2019 (is_inlineable = 0): the engine calls it row by row, in a serial
--       plan, and the plan shows none of the reads it does.
-- Clip V6.4 tells it, and measures both reports once rewritten.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
CREATE OR ALTER PROCEDURE Report.RevenueByCourse
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CourseId int, @Amount decimal(19, 2), @Total decimal(19, 2) = 0,
            @Current int = NULL, @RunningTotal decimal(19, 2) = 0, @DocumentCount int = 0;
    DECLARE @Result TABLE (CourseId int PRIMARY KEY, NetRevenue decimal(19, 2), DocumentCount int);

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT s.CourseId, i.NetAmount
        FROM Enrollment.Invoice AS i
        JOIN Course.Session AS s ON s.SessionId = i.SessionId
        ORDER BY s.CourseId;
    OPEN c;
    FETCH NEXT FROM c INTO @CourseId, @Amount;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @Current IS NULL OR @CourseId <> @Current
        BEGIN
            IF @Current IS NOT NULL INSERT @Result VALUES (@Current, @RunningTotal, @DocumentCount);
            SELECT @Current = @CourseId, @RunningTotal = 0, @DocumentCount = 0;
        END;
        SET @RunningTotal += @Amount;
        SET @DocumentCount += 1;
        SET @Total += @Amount;
        FETCH NEXT FROM c INTO @CourseId, @Amount;
    END;
    IF @Current IS NOT NULL INSERT @Result VALUES (@Current, @RunningTotal, @DocumentCount);
    CLOSE c;
    DEALLOCATE c;

    SELECT CourseId, NetRevenue, DocumentCount,
           CAST(100 * NetRevenue / NULLIF(@Total, 0) AS decimal(5, 2)) AS SharePct
    FROM @Result
    ORDER BY CourseId;
END;
GO
CREATE OR ALTER FUNCTION Enrollment.GetInvoiceStatus (@InvoiceCode varchar(50))
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
    ELSE IF @Due >= CAST(GETDATE() AS date) SET @Status = 'PENDING';
    ELSE SET @Status = 'UNPAID';
    RETURN @Status;
END;
GO
CREATE OR ALTER PROCEDURE Report.InvoiceList
    @Start date,
    @End   date
AS
BEGIN
    SET NOCOUNT ON;
    SELECT i.InvoiceCode, i.InvoiceDate, i.DueDate,
           COALESCE(co.Name, c.LastName + ISNULL(' ' + c.FirstName, '')) AS Customer,
           i.GrossAmount,
           Enrollment.GetInvoiceStatus(i.InvoiceCode) AS Status
    FROM Enrollment.Invoice AS i
    LEFT JOIN Contact.Company AS co ON co.CompanyId = i.CompanyId
    LEFT JOIN Contact.Contact AS c ON c.ContactId = i.ContactId
    WHERE i.InvoiceDate >= @Start AND i.InvoiceDate <= @End
      AND i.DocumentType = 'I'
    ORDER BY i.InvoiceDate, i.InvoiceCode;
END;
GO
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS Module, is_inlineable
FROM sys.sql_modules
WHERE object_id IN (OBJECT_ID(N'Report.RevenueByCourse'), OBJECT_ID(N'Enrollment.GetInvoiceStatus'),
                    OBJECT_ID(N'Report.InvoiceList'))
ORDER BY Module;
GO
