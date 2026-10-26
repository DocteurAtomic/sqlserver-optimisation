-- Module 2, setup: restores PachadataTraining as delivered, at compatibility level 170.
-- No sabotage in this module: it gives the notions the other modules use (pages, cache,
-- log, schedulers, configuration scopes). Runs on the lab, in one session.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
SELECT name, compatibility_level, recovery_model_desc, is_read_committed_snapshot_on
FROM sys.databases
WHERE name = N'PachadataTraining';
