-- Module D1 exercise: start. Runs on your lab, in one session.
-- ci: skip (the exercise changes the configuration of the instance)
-- Restores PachadataTraining as delivered (database MAXDOP 2), then shows the settings the
-- exercise works on. Play it after 99-cleanup.sql of the module: the instance is then at
-- the values of the lab (max server memory 2,147,483,647, MAXDOP 0, cost threshold 5).
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
SELECT name, value_in_use
FROM sys.configurations
WHERE name IN (N'max server memory (MB)', N'max degree of parallelism',
               N'cost threshold for parallelism', N'show advanced options')
ORDER BY name;
SELECT name, value
FROM PachadataTraining.sys.database_scoped_configurations
WHERE name = N'MAXDOP';
SELECT physical_memory_kb / 1024 AS physical_memory_mb, max_workers_count,
       committed_target_kb / 1024 AS target_mb
FROM sys.dm_os_sys_info;
GO
USE PachadataTraining;
GO
-- The query of part 1: the contacts who received the most e-mails, over the 4 million
-- deliveries. Run it in a NEW query window, once with each hint (MAXDOP 4, then MAXDOP 1).
SELECT TOP (5) ContactId, COUNT(*) AS Deliveries, SUM(CAST(Opened AS int)) AS Opened
FROM Marketing.Delivery
GROUP BY ContactId
ORDER BY Deliveries DESC
OPTION (MAXDOP 4);
GO
-- The query of part 2: the cities with the most prospects.
SELECT TOP (10) City, COUNT(*) AS Prospects
FROM Contact.ProspectUS
GROUP BY City
ORDER BY Prospects DESC;
