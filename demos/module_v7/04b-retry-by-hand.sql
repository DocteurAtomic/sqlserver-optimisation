-- Module V7, clip 4: the same deadlock, with a retry. Runs on the lab, after
-- 04a-deadlock-by-hand.sql, without the load.
-- ci: skip (two sessions: open two query windows, paste each part in its own window, start
-- them within a second)
-- The same numbering, inside a TRY ... CATCH that tries again when the transaction is chosen
-- as a deadlock victim (error 1205), three times at most. The credit notes stay in the base
-- until the next 00-setup.sql.

-- Session 1
USE PachadataTraining;
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Last int, @Try int = 1;
WHILE 1 = 1
BEGIN
    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        BEGIN TRANSACTION;
            SELECT @Last = ISNULL(MAX(CAST(RIGHT(InvoiceCode, 6) AS int)), 0)
            FROM Enrollment.Invoice
            WHERE InvoiceCode LIKE 'AV2026-%';
            -- The credit note is built here.
            WAITFOR DELAY '00:00:02';
            INSERT Enrollment.Invoice (InvoiceCode, Discount, CreationDate, InvoiceDate, ReminderLevel,
                                       NetAmount, GrossAmount, VatRate, DocumentType, OriginalInvoiceCode,
                                       CompanyId, ContactId, Reason, SessionId)
            SELECT 'AV2026-' + RIGHT('000000' + CAST(@Last + 1 AS varchar(10)), 6), i.Discount,
                   '20261018', '20261018', 0, -i.NetAmount, -i.GrossAmount, i.VatRate, 'C',
                   i.InvoiceCode, i.CompanyId, i.ContactId, 'Goodwill gesture', i.SessionId
            FROM Enrollment.Invoice AS i
            WHERE i.InvoiceCode = 'FA2026-007199';
        COMMIT;
        BREAK;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        -- Only a deadlock victim tries again, three times at most, after a short pause.
        IF ERROR_NUMBER() <> 1205 OR @Try = 3 THROW;
        PRINT CONCAT('Deadlock victim, try ', @Try, ' rolled back; trying again.');
        SET @Try += 1;
        WAITFOR DELAY '00:00:00.100';
    END CATCH;
END;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT 'AV2026-' + RIGHT('000000' + CAST(@Last + 1 AS varchar(10)), 6) AS CreditNote, @Try AS tries;
GO

-- Session 2
USE PachadataTraining;
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Last int, @Try int = 1;
WHILE 1 = 1
BEGIN
    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        BEGIN TRANSACTION;
            SELECT @Last = ISNULL(MAX(CAST(RIGHT(InvoiceCode, 6) AS int)), 0)
            FROM Enrollment.Invoice
            WHERE InvoiceCode LIKE 'AV2026-%';
            -- The credit note is built here.
            WAITFOR DELAY '00:00:02';
            INSERT Enrollment.Invoice (InvoiceCode, Discount, CreationDate, InvoiceDate, ReminderLevel,
                                       NetAmount, GrossAmount, VatRate, DocumentType, OriginalInvoiceCode,
                                       CompanyId, ContactId, Reason, SessionId)
            SELECT 'AV2026-' + RIGHT('000000' + CAST(@Last + 1 AS varchar(10)), 6), i.Discount,
                   '20261018', '20261018', 0, -i.NetAmount, -i.GrossAmount, i.VatRate, 'C',
                   i.InvoiceCode, i.CompanyId, i.ContactId, 'Goodwill gesture', i.SessionId
            FROM Enrollment.Invoice AS i
            WHERE i.InvoiceCode = 'FA2026-006199';
        COMMIT;
        BREAK;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        -- Only a deadlock victim tries again, three times at most, after a short pause.
        IF ERROR_NUMBER() <> 1205 OR @Try = 3 THROW;
        PRINT CONCAT('Deadlock victim, try ', @Try, ' rolled back; trying again.');
        SET @Try += 1;
        WAITFOR DELAY '00:00:00.100';
    END CATCH;
END;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT 'AV2026-' + RIGHT('000000' + CAST(@Last + 1 AS varchar(10)), 6) AS CreditNote, @Try AS tries;
GO
