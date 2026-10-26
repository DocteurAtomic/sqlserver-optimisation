-- Module D3, setup. Runs in one session on the lab, before the first clip of the module.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170 (PARAMETERIZATION
--    SIMPLE, Query Store in capture mode ALL, as the backup has them).
-- 2. The problem of the module is a load, not a setting: start ./demos/module_d3/charge.sh
--    afterwards. Its eight sessions play the new version of the website, which writes the
--    identifier of the learner or of the campaign e-mail into the text of each query (string
--    concatenation) instead of passing it as a parameter. Every identifier makes a new
--    text, so a new compilation and a new plan in the cache, used once.
-- The video plays the module on a throwaway copy of the lab (container sqlopt-d3): clips
-- D3.3 and D3.4 change the instance (optimize for ad hoc workloads, an Agent job). On your
-- lab, play 99-cleanup.sql at the end of the module.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
SELECT name, is_parameterization_forced, compatibility_level
FROM sys.databases
WHERE name = N'PachadataTraining';
SELECT name, value_in_use
FROM sys.configurations
WHERE name = N'optimize for ad hoc workloads';
