-- ci: skip (two sessions: run this one, then 3b-window-2.sql in another window within
-- five seconds)
-- Module 5 exercise, part 2, window 1: the cashier records the deposit slip of a check,
-- then clears the reminder of the invoice it pays.
USE PachadataTraining;
SET NOCOUNT ON;
SELECT @@SPID AS SessionId;
BEGIN TRANSACTION;
UPDATE Enrollment.Payment
SET SlipNumber = 'B605099'
WHERE PaymentId = 106875;

WAITFOR DELAY '00:00:05';

UPDATE Enrollment.Invoice
SET ReminderLevel = 0, ReminderDate = NULL
WHERE InvoiceCode = 'FA2026-006089';
COMMIT;
SELECT 'window 1 committed' AS Result;
