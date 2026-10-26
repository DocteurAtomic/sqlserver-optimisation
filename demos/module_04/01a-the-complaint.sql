-- Clip 4.1: the complaint. The back office looks for a contact by last name, and it has
-- been slow since this morning. Runs on the lab, in one session, after 00-setup.sql.
-- Messages of STATISTICS IO and TIME are in the Messages tab of SSMS.
USE PachadataTraining;
SET NOCOUNT ON;
SET ARITHABORT ON;  -- as in SSMS and in 00-setup.sql
GO
-- Two contacts are called Arsac.
SET STATISTICS IO, TIME ON;
EXEC Contact.GetContactByName @LastName = N'Arsac';
SET STATISTICS IO, TIME OFF;
GO
-- What the plan cache knows about the procedure: one plan, and only since it was compiled.
SELECT ps.cached_time, ps.execution_count,
       ps.total_logical_reads / ps.execution_count AS avg_logical_reads,
       ps.total_worker_time / ps.execution_count AS avg_cpu_us
FROM sys.dm_exec_procedure_stats AS ps
WHERE ps.database_id = DB_ID()
  AND ps.object_id = OBJECT_ID(N'Contact.GetContactByName');
