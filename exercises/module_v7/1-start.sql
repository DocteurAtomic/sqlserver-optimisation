-- Exercise of module V7, start. Runs on the lab, in one session. It lasts a few seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170 (row versioning,
--    READ_COMMITTED_SNAPSHOT, is ON in the delivered base).
-- 2. Creates Enrollment.AddInvoiceLine, the procedure the accounting team uses to add a
--    line to an invoice (a fee, a correction): it numbers the line as MAX + 1 of the lines
--    of the invoice, prices it (a WAITFOR of two seconds stands for the call to the pricing
--    service), inserts it, then updates the amounts of the invoice.
-- 3. Shows the invoice and the sessions the exercise works on.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
CREATE OR ALTER PROCEDURE Enrollment.AddInvoiceLine
    @InvoiceCode varchar(50),
    @Label varchar(200),
    @Quantity decimal(9, 2),
    @UnitPrice decimal(9, 2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @LineNumber smallint, @NetAmount decimal(9, 2) = ROUND(@Quantity * @UnitPrice, 2);

    BEGIN TRANSACTION;
        -- The next line number of the invoice.
        SELECT @LineNumber = ISNULL(MAX(LineNumber), 0) + 1
        FROM Enrollment.InvoiceLine
        WHERE InvoiceCode = @InvoiceCode;

        -- The line is priced here, by the pricing service.
        WAITFOR DELAY '00:00:02';

        INSERT Enrollment.InvoiceLine (InvoiceCode, LineNumber, LineTypeCode, EnrollmentId,
                                       Label, Quantity, UnitPrice, NetAmount)
        VALUES (@InvoiceCode, @LineNumber, 'FEE', NULL, @Label, @Quantity, @UnitPrice, @NetAmount);

        -- The amounts of the invoice follow its lines.
        UPDATE Enrollment.Invoice
        SET NetAmount = NetAmount + @NetAmount,
            GrossAmount = ROUND((NetAmount + @NetAmount) * (1 + VatRate / 100), 2)
        WHERE InvoiceCode = @InvoiceCode;
    COMMIT;

    SELECT @InvoiceCode AS InvoiceCode, @LineNumber AS LineNumber;
END;
GO
SET NOCOUNT ON;
SELECT name, is_read_committed_snapshot_on
FROM sys.databases
WHERE name = DB_NAME();
-- Part 3 works on this invoice.
SELECT i.InvoiceCode, i.NetAmount, i.GrossAmount, COUNT(l.LineNumber) AS lines, MAX(l.LineNumber) AS last_line
FROM Enrollment.Invoice AS i
JOIN Enrollment.InvoiceLine AS l ON l.InvoiceCode = i.InvoiceCode
WHERE i.InvoiceCode = 'FA2026-007300'
GROUP BY i.InvoiceCode, i.NetAmount, i.GrossAmount;
-- Parts 1 and 2 work on the sessions of the catalog.
SELECT COUNT(*) AS sessions, MIN(StartDate) AS first_start, MAX(StartDate) AS last_start
FROM Course.Session;
GO
