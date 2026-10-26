-- Module V7, clip 5: the fix. Runs on the lab, in one session, after 00-setup.sql (or after
-- 05a-optimized-locking.sql: every step can be run again).
-- Stop the load first: the ALTER DATABASE need the base alone.
-- 1. Row versioning back on (READ_COMMITTED_SNAPSHOT), as in the delivered base.
-- 2. Accelerated database recovery and optimized locking on.
-- 3. Enrollment.IssueCreditNote: the call to the accounting software after the COMMIT, and
--    the number read by MAX + 1 under UPDLOCK and HOLDLOCK, continuous and without
--    duplicates.
-- Then run the load again: ./demos/module_v7/charge.sh
USE master;
GO
ALTER DATABASE PachadataTraining SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE PachadataTraining SET ACCELERATED_DATABASE_RECOVERY = ON WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE PachadataTraining SET OPTIMIZED_LOCKING = ON WITH ROLLBACK IMMEDIATE;
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

        -- The next number of the year: the last one, plus one, read under an update lock
        -- kept on the range until the end of the transaction (UPDLOCK, HOLDLOCK). The
        -- second accountant waits here for the first one to commit, a few milliseconds now
        -- that the call to the accounting software is out of the transaction.
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

    COMMIT;

    -- The credit note goes to the accounting software, once it is committed. If the call
    -- fails, the credit note exists and the export is retried later, outside any transaction.
    WAITFOR DELAY '00:00:03';

    SELECT @CreditNote AS CreditNote;
END;
GO
DROP SEQUENCE IF EXISTS Enrollment.CreditNoteNumber;
GO
SELECT name, is_read_committed_snapshot_on, is_accelerated_database_recovery_on,
       is_optimized_locking_on
FROM sys.databases
WHERE name = DB_NAME();
GO
