-- ci: skip (three sessions: run this one first, then 05c-blocked-update.sql, then 05d-watch.sql)
-- Clip 2.3, session 1: a transaction that changes an invoice and keeps its lock for
-- 40 seconds before committing.
USE PachadataTraining;
SET NOCOUNT ON;
BEGIN TRANSACTION;
UPDATE Enrollment.Invoice
SET OrderReference = 'PO 4567829176-B'
WHERE InvoiceCode = 'FA2026-007500';
SELECT @@SPID AS SessionId, SYSDATETIME() AS LockedAt;

WAITFOR DELAY '00:00:40';
COMMIT;
SELECT SYSDATETIME() AS CommittedAt;
