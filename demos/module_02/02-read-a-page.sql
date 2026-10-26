-- Clip 2.1: one page of Elearning.Activity, its header and its rows.
-- Runs on the lab, in one session. Page numbers depend on the restore: read yours.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- Where is the event 1,000,000? %%physloc%% is undocumented: file, page and slot.
SELECT ActivityId, EventTime, EventTypeCode,
       sys.fn_PhysLocFormatter(%%physloc%%) AS Location
FROM Elearning.Activity
WHERE ActivityId = 1000000;
GO
-- The header of that page, through the documented function (SQL Server 2019 and later).
DECLARE @file int, @page int;
SELECT @file = plc.file_id, @page = plc.page_id
FROM Elearning.Activity
CROSS APPLY sys.fn_PhysLocCracker(%%physloc%%) AS plc
WHERE ActivityId = 1000000;

SELECT page_type_desc, OBJECT_NAME(object_id) AS ObjectName, index_id,
       slot_count, free_bytes, ghost_rec_count, page_lsn
FROM sys.dm_db_page_info(DB_ID(), @file, @page, 'DETAILED');

-- The page itself: DBCC PAGE is undocumented. WITH TABLERESULTS returns one row per field,
-- that a temporary table keeps for filtering. In SSMS, DBCC TRACEON (3604) then DBCC PAGE
-- without TABLERESULTS shows the same output as text in the Messages tab.
CREATE TABLE #Page (ParentObject nvarchar(255), Object nvarchar(255), Field nvarchar(255), Value nvarchar(4000));
DECLARE @dbcc nvarchar(200) = N'DBCC PAGE (' + CAST(DB_ID() AS nvarchar(10)) + N', '
    + CAST(@file AS nvarchar(10)) + N', ' + CAST(@page AS nvarchar(10)) + N', 3) WITH TABLERESULTS, NO_INFOMSGS;';
INSERT #Page EXEC (@dbcc);

-- The header: page type, number of slots, free bytes.
SELECT Field, Value
FROM #Page
WHERE ParentObject = N'PAGE HEADER:' AND Field IN (N'm_type', N'm_slotCnt', N'm_freeCnt', N'm_freeData');

-- The slot of the event 1,000,000: its offset in the page, its length, its columns.
DECLARE @slot int;
SELECT @slot = plc.slot_id
FROM Elearning.Activity
CROSS APPLY sys.fn_PhysLocCracker(%%physloc%%) AS plc
WHERE ActivityId = 1000000;

SELECT TOP (1) Object AS SlotHeader
FROM #Page
WHERE Object LIKE N'Slot ' + CAST(@slot AS nvarchar(10)) + N' Offset%';

SELECT Field, Value
FROM #Page
WHERE ParentObject LIKE N'Slot ' + CAST(@slot AS nvarchar(10)) + N' Offset%'
  AND Object LIKE N'Slot ' + CAST(@slot AS nvarchar(10)) + N' Column%';
GO
-- Rows per page, and the average size of a row, over the whole table.
SELECT page_count, record_count,
       CAST(1.0 * record_count / page_count AS decimal(6, 1)) AS rows_per_page,
       CAST(avg_record_size_in_bytes AS decimal(5, 1)) AS avg_record_bytes
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'Elearning.Activity'), 0, NULL, 'DETAILED');
