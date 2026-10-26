-- Module V7, clip 4: a deadlock on the credit note counter, in two sessions. Runs on the
-- lab, after 03a-rcsi-on.sql, without the load.
-- ci: skip (two sessions: open two query windows, paste each part in its own window, start
-- them within a second)
-- A first attempt to protect the counter: the numbering read in SERIALIZABLE, which keeps
-- shared range locks (RangeS-S) on the credit notes of 2026 until the end. Both sessions get
-- them, both then ask for an insert range lock that the other one's RangeS-S refuses: one of
-- them is chosen as the victim (error 1205). The credit note of the survivor stays in the
-- base until the next 00-setup.sql.

-- Session 1
USE PachadataTraining;
SET NOCOUNT ON;
DECLARE @Last int;
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
    WHERE i.InvoiceCode = 'FA2026-007200';
COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT 'AV2026-' + RIGHT('000000' + CAST(@Last + 1 AS varchar(10)), 6) AS CreditNote;
GO

-- Session 2
USE PachadataTraining;
SET NOCOUNT ON;
DECLARE @Last int;
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
    WHERE i.InvoiceCode = 'FA2026-006200';
COMMIT;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT 'AV2026-' + RIGHT('000000' + CAST(@Last + 1 AS varchar(10)), 6) AS CreditNote;
GO
