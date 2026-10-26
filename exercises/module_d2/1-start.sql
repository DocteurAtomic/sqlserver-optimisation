-- Module D2 exercise: start. Runs on your lab, in one session.
-- Restores PachadataTraining as delivered, then shows the files and the objects of the
-- exercise. Part 1 reads PachadataTraining; parts 2 and 3 work on a database of their own,
-- ExoStorage, which the solution creates and drops.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
SET NOCOUNT ON;
-- The files of the database, and the default folders of the instance.
SELECT name, type_desc, size / 128 AS size_mb,
       CASE WHEN is_percent_growth = 1 THEN CONCAT(growth, ' %')
            ELSE CONCAT(growth / 128, ' MB') END AS growth
FROM sys.database_files;
SELECT SERVERPROPERTY('InstanceDefaultDataPath') AS data_path,
       SERVERPROPERTY('InstanceDefaultLogPath') AS log_path;
-- Part 1: two tables to read cold. Contact.ProspectUS is a heap of one million prospects;
-- Marketing.Delivery has a clustered primary key on DeliveryId, 1 to 4,018,304.
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + OBJECT_NAME(object_id) AS table_name,
       SUM(row_count) AS row_count, SUM(used_page_count) / 128 AS used_mb
FROM sys.dm_db_partition_stats
WHERE object_id IN (OBJECT_ID(N'Contact.ProspectUS'), OBJECT_ID(N'Marketing.Delivery'))
  AND index_id IN (0, 1)
GROUP BY object_id;
GO
