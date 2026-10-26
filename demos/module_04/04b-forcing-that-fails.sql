-- Clip 4.4: a forced plan that can no longer be built. Runs on the lab, in one session, after
-- 04a-force-the-plan.sql. The index of the forced plan is disabled, then rebuilt.
USE PachadataTraining;
SET NOCOUNT ON;
SET ARITHABORT ON;  -- as in SSMS and in 00-setup.sql
GO
ALTER INDEX nix_contact_lastname ON Contact.Contact DISABLE;
GO
-- No error: the query runs with another plan.
SET STATISTICS IO ON;
EXEC Contact.GetContactByName @LastName = N'Arsac';
SET STATISTICS IO OFF;
GO
WAITFOR DELAY '00:00:02';  -- a new plan can take a second or two to show
SELECT p.plan_id, p.is_forced_plan, p.force_failure_count, p.last_force_failure_reason_desc
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
ORDER BY p.plan_id;
GO
-- The watch query: every forced plan that failed at least once.
SELECT p.query_id, p.plan_id, p.force_failure_count, p.last_force_failure_reason_desc
FROM sys.query_store_plan AS p
WHERE p.is_forced_plan = 1 AND p.force_failure_count > 0;
GO
-- The index rebuilt: the forced plan applies again.
ALTER INDEX nix_contact_lastname ON Contact.Contact REBUILD;
GO
SET STATISTICS IO ON;
EXEC Contact.GetContactByName @LastName = N'Arsac';
SET STATISTICS IO OFF;
