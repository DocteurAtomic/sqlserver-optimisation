-- Module V7, clip 3: the credit note number from a sequence. Runs on the lab, in one
-- session, after 03a-rcsi-on.sql.
-- Creates the sequence Enrollment.CreditNoteNumber, which starts after the last number of
-- 2026, and changes the procedure to take its number from it. The call to the accounting
-- software stays inside the transaction: only the numbering changes.
-- Then shows the gap a rolled-back credit note leaves. Lasts about ten seconds (three calls
-- of three seconds). Play 03b-counter-by-hand.sql again (other invoice numbers) afterwards.
USE PachadataTraining;
GO
SET NOCOUNT ON;
DROP SEQUENCE IF EXISTS Enrollment.CreditNoteNumber;
DECLARE @start int = (SELECT ISNULL(MAX(CAST(RIGHT(InvoiceCode, 6) AS int)), 0) + 1
                      FROM Enrollment.Invoice WHERE InvoiceCode LIKE 'AV2026-%');
DECLARE @sql nvarchar(max) = N'CREATE SEQUENCE Enrollment.CreditNoteNumber AS int START WITH '
                           + CAST(@start AS nvarchar(10)) + N' INCREMENT BY 1 NO CACHE;';
EXEC (@sql);
SELECT name, start_value, current_value, is_cached
FROM sys.sequences
WHERE name = N'CreditNoteNumber';
GO
CREATE OR ALTER PROCEDURE Enrollment.IssueCreditNote
    @InvoiceCode varchar(50),
    @Reason varchar(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    -- Today's date in the data.
    DECLARE @Today date = '20261018';
    DECLARE @CreditNote varchar(50);

    BEGIN TRANSACTION;
        -- A canceled invoice is no longer reminded.
        UPDATE Enrollment.Invoice
        SET ReminderLevel = 0, ReminderDate = NULL
        WHERE InvoiceCode = @InvoiceCode AND DocumentType = 'I';
        IF @@ROWCOUNT = 0
            THROW 50141, 'Unknown invoice.', 1;

        -- The next number of the year, from the sequence: no read of the table, no lock.
        SET @CreditNote = 'AV' + CAST(YEAR(@Today) AS char(4)) + '-'
                        + RIGHT('000000' + CAST(NEXT VALUE FOR Enrollment.CreditNoteNumber AS varchar(10)), 6);

        INSERT Enrollment.Invoice (InvoiceCode, Discount, CreationDate, InvoiceDate, ReminderLevel,
                                   NetAmount, GrossAmount, VatRate, DocumentType, OriginalInvoiceCode,
                                   CompanyId, ContactId, Reason, SessionId)
        SELECT @CreditNote, i.Discount, CAST(@Today AS smalldatetime), @Today, 0,
               -i.NetAmount, -i.GrossAmount, i.VatRate, 'C', i.InvoiceCode,
               i.CompanyId, i.ContactId, @Reason, i.SessionId
        FROM Enrollment.Invoice AS i
        WHERE i.InvoiceCode = @InvoiceCode;

        -- The credit note goes to the accounting software, called inside the transaction.
        WAITFOR DELAY '00:00:03';
    COMMIT;

    SELECT @CreditNote AS CreditNote;
END;
GO
-- A credit note issued, then one issued inside a transaction that the caller rolls back,
-- then a third one.
SET NOCOUNT ON;
DECLARE @issued TABLE (CreditNote varchar(50));
INSERT @issued EXEC Enrollment.IssueCreditNote @InvoiceCode = 'FA2026-007100', @Reason = 'Goodwill gesture';
BEGIN TRANSACTION;
    EXEC Enrollment.IssueCreditNote @InvoiceCode = 'FA2026-007099', @Reason = 'Goodwill gesture';
ROLLBACK;
INSERT @issued EXEC Enrollment.IssueCreditNote @InvoiceCode = 'FA2026-007098', @Reason = 'Goodwill gesture';
SELECT CreditNote FROM @issued;
SELECT InvoiceCode, OriginalInvoiceCode
FROM Enrollment.Invoice
WHERE InvoiceCode LIKE 'AV2026-%' AND OriginalInvoiceCode IN ('FA2026-007100', 'FA2026-007099', 'FA2026-007098')
ORDER BY InvoiceCode;
GO
