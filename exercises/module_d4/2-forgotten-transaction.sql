-- Module D4 exercise, part 1, question 3: a transaction left open. Runs in a second window
-- (window 2), started just before the UPDATE of window 1. Lasts two minutes and a half.
-- ci: skip (it only makes sense while window 1 runs part 1 of 3-solution.sql)
-- It updates one prospect in a transaction, then waits without committing, as a session
-- forgotten in SSMS would, and commits after two minutes and a half.
USE ExoTempdb;
SET NOCOUNT ON;
BEGIN TRANSACTION;
UPDATE dbo.Prospect SET City = UPPER(City) WHERE ProspectId = 1;
SELECT CONVERT(char(8), SYSDATETIME(), 108) AS opened_at, @@SPID AS session_id;
WAITFOR DELAY '00:02:30';
COMMIT;
SELECT CONVERT(char(8), SYSDATETIME(), 108) AS committed_at;
