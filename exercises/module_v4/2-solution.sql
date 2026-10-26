-- Exercise of module V4, solution. Runs on the lab, in one session, after 1-start.sql.
-- Part 1: the same aggregate on the heap in row mode, in batch mode, then on the columnstore.
-- Part 2: three writings of an average, and the one that loses the aggregate pushdown.
-- Part 3: the segments a filter skips. Part 4: the delta store, the delete bitmap and
-- REORGANIZE on Analytics.LoadTest, emptied at the end as it was delivered.
-- The figures quoted were measured on the lab (SORTIES.md of the module); the execution
-- mode and the locally aggregated rows are on the scan operator of the actual plan (Ctrl+M).
USE PachadataTraining;
GO
SET NOCOUNT ON;
-- A first read of the heap loads it in memory, so that part 1 compares warm scans.
SELECT COUNT_BIG(*) AS ActivityRows FROM Elearning.Activity;
GO
SET STATISTICS IO, TIME ON;
GO
-- Part 1.
-- 1. The heap, row mode forced: 31,151 pages, 2.4 to 2.9 seconds of CPU.
SELECT EventTypeCode, COUNT_BIG(*) AS Events, SUM(DurationSeconds) AS Seconds
FROM Elearning.Activity GROUP BY EventTypeCode
OPTION (USE HINT ('DISALLOW_BATCH_MODE'));
-- 2. The heap, batch mode chosen by the optimizer (level 170): the same 31,151 pages, about
--    1.2 seconds of CPU. Batch mode changes how the rows are processed, not what is read.
SELECT EventTypeCode, COUNT_BIG(*) AS Events, SUM(DurationSeconds) AS Seconds
FROM Elearning.Activity GROUP BY EventTypeCode;
-- 3. The columnstore: 2,909 LOB pages, 8 segments read, about 20 ms of CPU. The scan
--    shows Actual Number of Locally Aggregated Rows = 7,805,406 and passes 0 rows to its
--    parent: the whole aggregate is computed inside the scan (aggregate pushdown).
SELECT EventTypeCode, COUNT_BIG(*) AS Events, SUM(DurationSeconds) AS Seconds
FROM Analytics.ActivityFact GROUP BY EventTypeCode;
GO
-- Part 2.
-- 1. AVG(DurationSeconds / 60.0): the division is computed on each of the 7.8 million
--    rows before the aggregate, which then works on a numeric expression: no row is
--    aggregated in the scan, 190 to 240 ms of CPU.
-- 2. AVG(DurationSeconds) / 60.0: pushed down (about 20 ms) but wrong. AVG of an int is an
--    int: 147 seconds for a page instead of 147.75, so 2.45 minutes instead of 2.4625.
-- 3. SUM(DurationSeconds) / 60.0 / COUNT(DurationSeconds): the exact average of the first
--    query (COUNT of the column skips NULLs, as AVG does), with the aggregate pushed down:
--    about 20 ms. Aggregate in the column, compute on the result.
SELECT EventTypeCode, AVG(DurationSeconds / 60.0) AS AvgMinutes
FROM Analytics.ActivityFact GROUP BY EventTypeCode;
SELECT EventTypeCode, AVG(DurationSeconds) / 60.0 AS AvgMinutes
FROM Analytics.ActivityFact GROUP BY EventTypeCode;
SELECT EventTypeCode, SUM(DurationSeconds) / 60.0 / COUNT(DurationSeconds) AS AvgMinutes
FROM Analytics.ActivityFact GROUP BY EventTypeCode;
GO
-- Part 3.
-- 1. One year of EventTime: 2 segments read, 6 skipped. The table is ordered on EventTime
--    (ORDER clause), and each segment covers a stretch of time.
-- 2. One contact: 8 segments read, 0 skipped. Every segment holds contacts of the whole
--    range: the order on the date does nothing for this column.
SELECT TrainingLocationId, SUM(DurationSeconds) AS Seconds
FROM Analytics.ActivityFact
WHERE EventTime >= '20250101' AND EventTime < '20260101'
GROUP BY TrainingLocationId;
SELECT TrainingLocationId, SUM(DurationSeconds) AS Seconds
FROM Analytics.ActivityFact
WHERE ContactId = 556
GROUP BY TrainingLocationId;
GO
SET STATISTICS IO, TIME OFF;
GO
-- Part 4.
-- 1. 150,000 rows with TABLOCK: a parallel insert at the DOP of the database (2). Each
--    thread gets 75,000 rows, under the threshold of 102,400: two OPEN row groups in the
--    delta store, nothing compressed.
INSERT INTO Analytics.LoadTest WITH (TABLOCK)
SELECT TOP (150000) * FROM Analytics.ActivityFact;
SELECT row_group_id, state_desc, total_rows, deleted_rows, trim_reason_desc,
       transition_to_compressed_state_desc
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID(N'Analytics.LoadTest')
ORDER BY row_group_id;
GO
-- 2. The same rows on one thread: one COMPRESSED row group of 150,000 rows, trimmed by the
--    end of the load (BULKLOAD).
TRUNCATE TABLE Analytics.LoadTest;
INSERT INTO Analytics.LoadTest WITH (TABLOCK)
SELECT TOP (150000) * FROM Analytics.ActivityFact
OPTION (MAXDOP 1);
SELECT row_group_id, state_desc, total_rows, deleted_rows, trim_reason_desc,
       transition_to_compressed_state_desc
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID(N'Analytics.LoadTest')
ORDER BY row_group_id;
GO
-- 3. A delete and an update of compressed rows. The compressed group keeps its 150,000
--    rows with deleted_rows = 15,000: the 10,000 deleted rows and the 5,000 old versions of
--    the updated ones, marked in the delete bitmap. The 5,000 new versions go to an OPEN
--    group. 140,000 rows are visible; the scans still read the 150,000.
DELETE TOP (10000) FROM Analytics.LoadTest;
UPDATE TOP (5000) Analytics.LoadTest
SET DurationSeconds = DurationSeconds + 1
WHERE DurationSeconds IS NOT NULL;
SELECT row_group_id, state_desc, total_rows, deleted_rows, trim_reason_desc,
       transition_to_compressed_state_desc
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID(N'Analytics.LoadTest')
ORDER BY row_group_id;
SELECT COUNT_BIG(*) AS VisibleRows FROM Analytics.LoadTest;
GO
-- 4. REORGANIZE with COMPRESS_ALL_ROW_GROUPS: the OPEN group is compressed into a new group
--    (REORG_FORCED) and the old one becomes a TOMBSTONE.
ALTER INDEX ccix_LoadTest ON Analytics.LoadTest REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON);
SELECT row_group_id, state_desc, total_rows, deleted_rows, trim_reason_desc,
       transition_to_compressed_state_desc
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID(N'Analytics.LoadTest')
ORDER BY row_group_id;
GO
-- 5. REORGANIZE without option: the two compressed groups are merged into one group of
--    140,000 rows (MERGE), without the deleted rows. The replaced groups stay TOMBSTONE until
--    the tuple mover removes them.
ALTER INDEX ccix_LoadTest ON Analytics.LoadTest REORGANIZE;
SELECT row_group_id, state_desc, total_rows, deleted_rows, trim_reason_desc,
       transition_to_compressed_state_desc
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID(N'Analytics.LoadTest')
ORDER BY row_group_id;
GO
-- Cleanup: the table of the exercise is empty again, as delivered.
TRUNCATE TABLE Analytics.LoadTest;
GO
