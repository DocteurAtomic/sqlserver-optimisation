-- Module V7, clip 3: continuous numbering, without a sequence. Runs on the lab, in one
-- session, after 03c-sequence.sql.
-- A credit note is an invoice, and the numbers of invoices must follow each other without
-- gaps. The procedure goes back to MAX + 1, read with UPDLOCK and HOLDLOCK, as
-- Enrollment.IssueInvoices of the base numbers its invoices. The sequence is dropped.
-- The call to the accounting software stays inside the transaction: clip 5 moves it.
-- Play 03b-counter-by-hand.sql again (other invoice numbers) afterwards.
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

        -- The next number of the year: the last one, plus one, read under an update lock
        -- kept on the range until the end of the transaction (UPDLOCK, HOLDLOCK). The
        -- second accountant waits here for the first one to commit, then reads his number.
        SELECT @Last = ISNULL(MAX(CAST(RIGHT(InvoiceCode, 6) AS int)), 0)
        FROM Enrollment.Invoice WITH (UPDLOCK, HOLDLOCK)
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

        -- The credit note goes to the accounting software, called inside the transaction.
        WAITFOR DELAY '00:00:03';
    COMMIT;

    SELECT @CreditNote AS CreditNote;
END;
GO
DROP SEQUENCE IF EXISTS Enrollment.CreditNoteNumber;
GO
