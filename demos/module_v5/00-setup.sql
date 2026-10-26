-- Module V5, setup. Runs on the lab, in one session, before the first clip of the module.
-- It lasts a few seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. The problem of the module: turns off the parameter sensitive plan optimization of
--    SQL Server 2022 (PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = OFF) for the database. At
--    level 170 it is on by default, and it keeps two plans for Report.RecipientsByCampaign,
--    one for the small evaluation campaigns (1 to 20 deliveries) and one for the monthly
--    letters (107,994 deliveries). Without it, the procedure has one plan, compiled for the
--    first value it receives.
-- 3. Plays the morning of the marketing tool, with the session options of an application
--    (ARITHABORT OFF, the default of ODBC and of .NET; SSMS sets it ON): the export of the
--    September letter comes first and compiles the plan (a parallel hash join that scans
--    the 4 million deliveries), then the sender of the satisfaction surveys asks for the
--    recipients of the last twenty evaluations, each served by the plan of the letter.
--    The export returns the 107,994 recipients of the letter: in SSMS, Query Options,
--    Results, Grid, "Discard results after execution" spares the grid.
-- Clip V5.5 tells it, and measures the procedure once the optimization is back on.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = OFF;
GO
SET NOCOUNT ON;
SET ARITHABORT OFF;
-- The export of the September letter.
EXEC Report.RecipientsByCampaign @CampaignId = 36;
-- The sender of the satisfaction surveys: the last twenty evaluations, 4 to 20 recipients.
DECLARE @CampaignId int = 17371;
WHILE @CampaignId <= 17390
BEGIN
    EXEC Report.RecipientsByCampaign @CampaignId = @CampaignId;
    SET @CampaignId += 1;
END;
GO
SELECT name, value, is_value_default
FROM sys.database_scoped_configurations
WHERE name = N'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION';
SELECT execution_count, min_logical_reads, max_logical_reads,
       total_worker_time / execution_count / 1000 AS AvgCpuMs
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Report.RecipientsByCampaign');
