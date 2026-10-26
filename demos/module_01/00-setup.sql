-- Module 1, setup. Runs on the lab, in one session, before the first clip of the module.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. The problem of the module: drops the index nix_temp_01 of Enrollment.Enrollment
--    (key SessionId, included column CreationDate). The list of the enrollees of a session,
--    which the website sends all day long, then reads the whole table (596 pages) instead of
--    seeking its rows (23 pages). Module 3 reads its plan and recreates the index.
-- 3. Start the background load afterwards: ./demos/module_01/charge.sh
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
DROP INDEX nix_temp_01 ON Enrollment.Enrollment;
GO
SELECT i.name AS IndexName, i.type_desc AS IndexType
FROM sys.indexes AS i
WHERE i.object_id = OBJECT_ID(N'Enrollment.Enrollment')
ORDER BY i.index_id;
