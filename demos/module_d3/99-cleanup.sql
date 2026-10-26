-- Module D3, cleanup: puts the instance back as the lab was delivered. Runs in one session,
-- after charge.sh has stopped.
-- ci: skip (it changes the configuration of the instance and drops an Agent job)
-- Values read on a new container of the lab image (2025-CU7): optimize for ad hoc workloads
-- 0, show advanced options 0, no Agent job. PARAMETERIZATION FORCED is a database option:
-- the next module's 00-setup.sql restores PachadataTraining with SIMPLE. The snapshots
-- stay in PachadataDBA.
USE master;
SET NOCOUNT ON;
GO
EXEC sys.sp_configure N'show advanced options', 1;
RECONFIGURE;
EXEC sys.sp_configure N'optimize for ad hoc workloads', 0;
RECONFIGURE;
EXEC sys.sp_configure N'show advanced options', 0;
RECONFIGURE;
GO
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'PachadataDBA - snapshot')
    EXEC msdb.dbo.sp_delete_job @job_name = N'PachadataDBA - snapshot';
GO
SELECT name, value, value_in_use
FROM sys.configurations
WHERE name IN (N'optimize for ad hoc workloads', N'show advanced options')
ORDER BY name;
SELECT COUNT(*) AS snapshot_jobs
FROM msdb.dbo.sysjobs
WHERE name = N'PachadataDBA - snapshot';
