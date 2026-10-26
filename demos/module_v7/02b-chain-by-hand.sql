-- Module V7, clip 2: a blocking chain built by hand, in three sessions. Runs on the lab,
-- after 00-setup.sql, without the load.
-- ci: skip (three sessions: open three query windows, paste each part in its own window,
-- start them in order within a second, then run step 2 of 02a-blocking-chain.sql in a
-- fourth window before three seconds have passed)
-- Each credit note issued stays in the base until the next 00-setup.sql. Pick other invoice
-- numbers to play the scene again.

-- Session 1, the first accountant: cancels an invoice of October.
USE PachadataTraining;
EXEC Enrollment.IssueCreditNote @InvoiceCode = 'FA2026-007400', @Reason = 'Goodwill gesture';
GO

-- Session 2, the second accountant: cancels another invoice. Its procedure updates the
-- invoice, then waits on the numbering read, behind session 1.
USE PachadataTraining;
EXEC Enrollment.IssueCreditNote @InvoiceCode = 'FA2026-006400', @Reason = 'Goodwill gesture';
GO

-- Session 3, the customer area: displays the invoice that session 2 is canceling.
USE PachadataTraining;
SELECT InvoiceCode, InvoiceDate, DueDate, GrossAmount, ReminderLevel
FROM Enrollment.Invoice
WHERE InvoiceCode = 'FA2026-006400';
GO
