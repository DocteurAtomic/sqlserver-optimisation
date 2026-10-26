-- Module V7, clip 5: lock after qualification, in two sessions. Runs on the lab, after
-- 05a-optimized-locking.sql, without the load.
-- ci: skip (two sessions: open two query windows, paste each part in its own window, start
-- them within a second)
-- The first session updates one invoice by its number and keeps its transaction open ten seconds.
-- The second session updates another invoice, found by its purchase order reference, a column with
-- no index: the update reads the whole table, the row of session 1 included. Both roll back.
-- Played three times in the clip: with optimized locking (no wait), with optimized locking
-- turned off (session 2 waits for session 1), then with optimized locking and session 2
-- changed to update the same invoice as session 1 (it waits, on the transaction).
-- To turn optimized locking off, then on again (no other session in the base):
--   ALTER DATABASE PachadataTraining SET OPTIMIZED_LOCKING = OFF WITH ROLLBACK IMMEDIATE;
--   ALTER DATABASE PachadataTraining SET OPTIMIZED_LOCKING = ON WITH ROLLBACK IMMEDIATE;

-- Session 1
USE PachadataTraining;
BEGIN TRANSACTION;
UPDATE Enrollment.Invoice
SET ReminderLevel = 0, ReminderDate = NULL
WHERE InvoiceCode = 'FA2026-007000';
WAITFOR DELAY '00:00:10';
ROLLBACK;
GO

-- Session 2
USE PachadataTraining;
SET STATISTICS TIME ON;
BEGIN TRANSACTION;
UPDATE Enrollment.Invoice
SET ReminderLevel = 0, ReminderDate = NULL
WHERE OrderReference = 'PO 4533411083';
-- The same invoice as session 1, for the third run:
-- WHERE InvoiceCode = 'FA2026-007000';
ROLLBACK;
SET STATISTICS TIME OFF;
GO
