-- ci: skip (two sessions: run this one first, then 04b-log-held.sql in a second window)
-- Clip 2.2, session 1: a transaction opened and left open, as an application that forgot
-- its COMMIT. It changes one invoice, then waits 60 seconds before committing: run
-- 04b-log-held.sql in the meantime. In SSMS you can also run it up to the WAITFOR and
-- commit by hand.
USE PachadataTraining;
SET NOCOUNT ON;
BEGIN TRANSACTION;
UPDATE Enrollment.Invoice
SET OrderReference = 'PO 4567829176-B'
WHERE InvoiceCode = 'FA2026-007500';
SELECT @@SPID AS SessionId, @@TRANCOUNT AS OpenTransactions, SYSDATETIME() AS OpenedAt;

WAITFOR DELAY '00:01:00';
COMMIT;
SELECT @@TRANCOUNT AS OpenTransactions, SYSDATETIME() AS CommittedAt;
