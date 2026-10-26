/*
Module 2 exercise: pages, cache and log, on other tables than the demonstrations.
Restores PachadataTraining as delivered. Runs on the lab, in one session.
The questions are in README.md; the solution is 2-solution.sql.
Part 2 takes the database offline and back online: lab only, never on a production server.
*/
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS TableName,
       index_id, row_count, used_page_count
FROM sys.dm_db_partition_stats
WHERE object_id IN (OBJECT_ID(N'Contact.Contact'), OBJECT_ID(N'Contact.ProspectUS'),
                    OBJECT_ID(N'Contact.ProspectUS_N'))
  AND index_id IN (0, 1)
ORDER BY TableName;
