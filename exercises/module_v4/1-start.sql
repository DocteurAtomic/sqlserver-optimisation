-- Exercise of module V4, start. Runs on the lab, in one session. It lasts a few seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. Shows the tables of the exercise: Elearning.Activity, the activity log of the
--    e-learning platform (7.8 million rows, a heap); Analytics.ActivityFact, the same rows
--    in a clustered columnstore index ordered on EventTime; Analytics.LoadTest, an empty
--    table with the same columnstore structure.
-- 3. Gives the queries of the four parts.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
SELECT OBJECT_SCHEMA_NAME(i.object_id) + N'.' + OBJECT_NAME(i.object_id) AS TableName,
       i.name AS IndexName, i.type_desc,
       (SELECT SUM(p.rows) FROM sys.partitions AS p
        WHERE p.object_id = i.object_id AND p.index_id = i.index_id) AS TableRows
FROM sys.indexes AS i
WHERE i.object_id IN (OBJECT_ID(N'Elearning.Activity'), OBJECT_ID(N'Analytics.ActivityFact'),
                      OBJECT_ID(N'Analytics.LoadTest'));
GO
-- Part 1. The same aggregate three times. Run each with the actual plan (Ctrl+M) and
-- SET STATISTICS IO, TIME ON; note the pages read, the CPU time, the execution mode of the
-- scan and, on the columnstore, its Actual Number of Locally Aggregated Rows.
/*
SELECT EventTypeCode, COUNT_BIG(*) AS Events, SUM(DurationSeconds) AS Seconds
FROM Elearning.Activity GROUP BY EventTypeCode
OPTION (USE HINT ('DISALLOW_BATCH_MODE'));
SELECT EventTypeCode, COUNT_BIG(*) AS Events, SUM(DurationSeconds) AS Seconds
FROM Elearning.Activity GROUP BY EventTypeCode;
SELECT EventTypeCode, COUNT_BIG(*) AS Events, SUM(DurationSeconds) AS Seconds
FROM Analytics.ActivityFact GROUP BY EventTypeCode;
*/
-- Part 2. The average duration in minutes, written three ways. Which ones give the same
-- result? Which one costs ten times more CPU than the others, and why?
/*
SELECT EventTypeCode, AVG(DurationSeconds / 60.0) AS AvgMinutes
FROM Analytics.ActivityFact GROUP BY EventTypeCode;
SELECT EventTypeCode, AVG(DurationSeconds) / 60.0 AS AvgMinutes
FROM Analytics.ActivityFact GROUP BY EventTypeCode;
SELECT EventTypeCode, SUM(DurationSeconds) / 60.0 / COUNT(DurationSeconds) AS AvgMinutes
FROM Analytics.ActivityFact GROUP BY EventTypeCode;
*/
-- Part 3. Two filters on the columnstore: how many segments does each one read?
/*
SELECT TrainingLocationId, SUM(DurationSeconds) AS Seconds
FROM Analytics.ActivityFact
WHERE EventTime >= '20250101' AND EventTime < '20260101'
GROUP BY TrainingLocationId;
SELECT TrainingLocationId, SUM(DurationSeconds) AS Seconds
FROM Analytics.ActivityFact
WHERE ContactId = 556
GROUP BY TrainingLocationId;
*/
-- Part 4. Load Analytics.LoadTest: 150,000 rows with TABLOCK, then the same rows with
-- OPTION (MAXDOP 1) after a TRUNCATE; then delete 10,000 rows and update 5,000; then
-- ALTER INDEX ccix_LoadTest ON Analytics.LoadTest REORGANIZE, with and without
-- COMPRESS_ALL_ROW_GROUPS = ON. After each step, read the row groups:
/*
SELECT row_group_id, state_desc, total_rows, deleted_rows, trim_reason_desc,
       transition_to_compressed_state_desc
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID(N'Analytics.LoadTest')
ORDER BY row_group_id;
*/
