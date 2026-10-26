-- Module V7, clip 3: the credit note counter under row versioning, in three sessions.
-- Runs on the lab, after 03a-rcsi-on.sql, without the load.
-- ci: skip (three sessions: open three query windows, paste each part in its own window,
-- start them in order within a second)
-- The credit notes issued stay in the base until the next 00-setup.sql. Pick other invoice
-- numbers to play the scene again.

-- Session 1, the first accountant.
USE PachadataTraining;
EXEC Enrollment.IssueCreditNote @InvoiceCode = 'FA2026-007300', @Reason = 'Goodwill gesture';
GO

-- Session 2, the second accountant, a second later.
USE PachadataTraining;
EXEC Enrollment.IssueCreditNote @InvoiceCode = 'FA2026-006300', @Reason = 'Goodwill gesture';
GO

-- Session 3, the customer area: the invoice that session 2 is canceling, read at once.
USE PachadataTraining;
SELECT InvoiceCode, GrossAmount, ReminderLevel
FROM Enrollment.Invoice
WHERE InvoiceCode = 'FA2026-006300';
GO
