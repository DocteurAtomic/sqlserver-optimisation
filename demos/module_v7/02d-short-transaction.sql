-- Module V7, clip 2: the transaction shortened. Runs on the lab, in one session, after
-- 00-setup.sql.
-- The call to the accounting software moves after the COMMIT: the locks of the credit note
-- are released before the call, not after it. Nothing else changes, the numbering by
-- MAX + 1 included (clip 3).
-- Then play 02b-chain-by-hand.sql again (with other invoice numbers), or the load.
USE PachadataTraining;
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
    DECLARE @Last int, @CreditNote varchar(50);

    BEGIN TRANSACTION;
        -- A canceled invoice is no longer reminded.
        UPDATE Enrollment.Invoice
        SET ReminderLevel = 0, ReminderDate = NULL
        WHERE InvoiceCode = @InvoiceCode AND DocumentType = 'I';
        IF @@ROWCOUNT = 0
            THROW 50141, 'Unknown invoice.', 1;

        -- The next number of the year: the last one, plus one.
        SELECT @Last = ISNULL(MAX(CAST(RIGHT(InvoiceCode, 6) AS int)), 0)
        FROM Enrollment.Invoice
        WHERE InvoiceCode LIKE 'AV' + CAST(YEAR(@Today) AS char(4)) + '-%';
        SET @CreditNote = 'AV' + CAST(YEAR(@Today) AS char(4)) + '-'
                        + RIGHT('000000' + CAST(@Last + 1 AS varchar(10)), 6);

        INSERT Enrollment.Invoice (InvoiceCode, Discount, CreationDate, InvoiceDate, ReminderLevel,
                                   NetAmount, GrossAmount, VatRate, DocumentType, OriginalInvoiceCode,
                                   CompanyId, ContactId, Reason, SessionId)
        SELECT @CreditNote, i.Discount, CAST(@Today AS smalldatetime), @Today, 0,
               -i.NetAmount, -i.GrossAmount, i.VatRate, 'C', i.InvoiceCode,
               i.CompanyId, i.ContactId, @Reason, i.SessionId
        FROM Enrollment.Invoice AS i
        WHERE i.InvoiceCode = @InvoiceCode;
    COMMIT;

    -- The credit note goes to the accounting software, once it is committed.
    WAITFOR DELAY '00:00:03';

    SELECT @CreditNote AS CreditNote;
END;
GO
