-- Clip D4.2: which pages the portal sessions wait for. Runs on the lab, in one session,
-- while charge.sh runs (alone, the queries return no row). Lasts ten seconds.
USE master;
SET NOCOUNT ON;
GO
-- 1. A snapshot of the portal sessions: what each one is doing or waiting for.
SELECT ISNULL(r.wait_type, N'(running)') AS wait_type, COUNT(*) AS sessions
FROM sys.dm_exec_sessions AS s
JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
WHERE s.host_name LIKE N'portal-%'
GROUP BY r.wait_type
ORDER BY sessions DESC;

-- 2. Ten seconds of samples: every 100 ms, the tasks that wait for a page latch in tempdb
--    (database 2), with the page they wait for (resource_description, database:file:page).
CREATE TABLE #Samples (wait_type nvarchar(60), page nvarchar(100));
DECLARE @i int = 0;
WHILE @i < 100
BEGIN
    INSERT INTO #Samples (wait_type, page)
    SELECT wait_type, LEFT(resource_description, CHARINDEX(N' ', resource_description + N' ') - 1)
    FROM sys.dm_os_waiting_tasks
    WHERE wait_type LIKE N'PAGELATCH[_]%'
      AND resource_description LIKE N'2:%';
    WAITFOR DELAY '00:00:00.100';
    SET @i += 1;
END;

-- Each page, with the object it belongs to (sys.dm_db_page_info, SQL Server 2019 and later)
-- and its kind: PFS, GAM and SGAM are the allocation pages, at fixed places in each file
-- (pages 1, 2 and 3, then every 8,088 pages for PFS and every 511,232 for GAM and SGAM).
WITH pages AS (
    SELECT wait_type, page,
           CAST(PARSENAME(REPLACE(page, N':', N'.'), 2) AS int) AS file_id,
           CAST(PARSENAME(REPLACE(page, N':', N'.'), 1) AS int) AS page_id
    FROM #Samples
)
SELECT TOP (8) p.wait_type, p.page, COUNT(*) AS samples,
       OBJECT_NAME(pi.object_id, 2) AS object_name,
       CASE WHEN p.page_id = 1 OR (p.page_id > 0 AND p.page_id % 8088 = 0) THEN N'PFS'
            WHEN p.page_id = 2 OR (p.page_id > 2 AND p.page_id % 511232 = 0) THEN N'GAM'
            WHEN p.page_id = 3 OR (p.page_id > 3 AND p.page_id % 511232 = 1) THEN N'SGAM'
            ELSE N'' END AS allocation_page
FROM pages AS p
CROSS APPLY sys.dm_db_page_info(2, p.file_id, p.page_id, 'LIMITED') AS pi
GROUP BY p.wait_type, p.page, p.page_id, pi.object_id
ORDER BY samples DESC;

-- The same samples, by object and wait type.
WITH pages AS (
    SELECT wait_type,
           CAST(PARSENAME(REPLACE(page, N':', N'.'), 2) AS int) AS file_id,
           CAST(PARSENAME(REPLACE(page, N':', N'.'), 1) AS int) AS page_id
    FROM #Samples
)
SELECT OBJECT_NAME(pi.object_id, 2) AS object_name,
       SUM(IIF(p.wait_type = N'PAGELATCH_EX', 1, 0)) AS ex_samples,
       SUM(IIF(p.wait_type = N'PAGELATCH_SH', 1, 0)) AS sh_samples,
       SUM(IIF(p.wait_type = N'PAGELATCH_UP', 1, 0)) AS up_samples
FROM pages AS p
CROSS APPLY sys.dm_db_page_info(2, p.file_id, p.page_id, 'LIMITED') AS pi
GROUP BY pi.object_id
ORDER BY COUNT(*) DESC;

-- 3. The diagnostic query of the tempdb page on Microsoft Learn: the sessions that wait,
--    right now, on a page of the system tables of tempdb that hold the metadata of
--    temporary objects. Its list of object_id leaves out 7, sysallocunits.
SELECT OBJECT_NAME(dpi.object_id, dpi.database_id) AS system_table_name,
       COUNT(DISTINCT r.session_id) AS session_count
FROM sys.dm_exec_requests AS r
CROSS APPLY sys.fn_PageResCracker(r.page_resource) AS prc
CROSS APPLY sys.dm_db_page_info(prc.db_id, prc.file_id, prc.page_id, 'LIMITED') AS dpi
WHERE dpi.database_id = 2
  AND dpi.object_id IN (3, 9, 34, 40, 41, 54, 55, 60, 74, 75)
  AND UPPER(r.wait_type) LIKE N'PAGELATCH[_]%'
GROUP BY dpi.object_id, dpi.database_id;
