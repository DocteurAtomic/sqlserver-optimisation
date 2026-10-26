-- Module V7, setup. Runs on the lab, in one session, before the first clip of the module.
-- It lasts a few seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. The problem of the module, three changes:
--    a. READ_COMMITTED_SNAPSHOT is turned OFF on the base (it is ON in the delivered base):
--       a reader in READ COMMITTED takes shared locks again and waits for the writers.
--    b. Enrollment.IssueCreditNote, the procedure the accounting team runs to cancel an
--       invoice, stops the reminders of the invoice, numbers the credit note and inserts
--       it, then sends it to the accounting software (a WAITFOR of 3 seconds stands for
--       that call), all inside one transaction. Its locks are held during the call.
--    c. The credit note number is computed as MAX + 1 of the numbers of the year. With
--       locking reads, the second accountant waits for the first one and reads the right
--       number. With row versioning, both read the same number, and the second insert
--       fails on the primary key (error 2627).
-- 3. Start the load afterwards: ./demos/module_v7/charge.sh
-- Clip V7.5 tells it, and measures the fix.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
ALTER DATABASE PachadataTraining SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;
GO
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

        -- The credit note goes to the accounting software, called inside the transaction.
        WAITFOR DELAY '00:00:03';
    COMMIT;

    SELECT @CreditNote AS CreditNote;
END;
GO
SELECT name, is_read_committed_snapshot_on, is_accelerated_database_recovery_on,
       is_optimized_locking_on
FROM sys.databases
WHERE name = DB_NAME();
GO
