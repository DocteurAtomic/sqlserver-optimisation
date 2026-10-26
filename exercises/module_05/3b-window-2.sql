-- ci: skip (two sessions: run 3a-window-1.sql first, in another window)
-- Module 5 exercise, part 2, window 2: the accountant sends a second reminder for the
-- invoice, then writes the check number again on its payment.
USE PachadataTraining;
SET NOCOUNT ON;
SELECT @@SPID AS SessionId;
BEGIN TRANSACTION;
UPDATE Enrollment.Invoice
SET ReminderLevel = 2, ReminderDate = '20261026'
WHERE InvoiceCode = 'FA2026-006089';

WAITFOR DELAY '00:00:05';

UPDATE Enrollment.Payment
SET CheckNumber = '2477912'
WHERE PaymentId = 106875;
COMMIT;
SELECT 'window 2 committed' AS Result;
