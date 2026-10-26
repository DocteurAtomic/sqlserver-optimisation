-- Clip D4.1: who uses tempdb, and how. Runs on the lab, in one session, while charge.sh
-- runs (it also runs alone, and then shows a lab at rest). Lasts ten seconds.
USE master;
SET NOCOUNT ON;
GO
-- 1. Per session: the pages each portal session has allocated and deallocated in tempdb
--    since it connected. sys.dm_db_session_space_usage is updated at the end of each task:
--    the call that is running right now shows only in sys.dm_db_task_space_usage.
SELECT COUNT(*) AS portal_sessions,
       SUM(su.user_objects_alloc_page_count)   AS session_user_alloc,
       SUM(su.user_objects_dealloc_page_count) AS session_user_dealloc,
       SUM(tu.user_alloc)                      AS task_user_alloc,
       SUM(tu.user_dealloc)                    AS task_user_dealloc,
       SUM(tu.internal_alloc)                  AS task_internal_alloc
FROM sys.dm_exec_sessions AS s
JOIN sys.dm_db_session_space_usage AS su ON su.session_id = s.session_id
OUTER APPLY (SELECT SUM(t.user_objects_alloc_page_count)     AS user_alloc,
                    SUM(t.user_objects_dealloc_page_count)   AS user_dealloc,
                    SUM(t.internal_objects_alloc_page_count) AS internal_alloc
             FROM sys.dm_db_task_space_usage AS t
             WHERE t.session_id = s.session_id) AS tu
WHERE s.host_name LIKE N'portal-%';

-- 2. The rhythm: the temporary tables of the instance over ten seconds. Temp Tables
--    Creation Rate is a cumulative counter (type 272696576), despite its name: the rate is
--    the difference divided by the seconds. Active Temp Tables and Temp Tables For
--    Destruction are instant values: the second counts the dropped tables that wait for
--    the background task that deallocates them.
DECLARE @c0 bigint, @t0 datetime2 = SYSDATETIME();
SELECT @c0 = cntr_value
FROM sys.dm_os_performance_counters
WHERE RTRIM(object_name) LIKE N'%:General Statistics'
  AND RTRIM(counter_name) = N'Temp Tables Creation Rate';
WAITFOR DELAY '00:00:10';
SELECT CAST((p.cntr_value - @c0) / (DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0) AS decimal(9, 0)) AS temp_tables_created_per_s,
       (SELECT cntr_value FROM sys.dm_os_performance_counters
        WHERE RTRIM(object_name) LIKE N'%:General Statistics'
          AND RTRIM(counter_name) = N'Active Temp Tables') AS active_temp_tables,
       (SELECT cntr_value FROM sys.dm_os_performance_counters
        WHERE RTRIM(object_name) LIKE N'%:General Statistics'
          AND RTRIM(counter_name) = N'Temp Tables For Destruction') AS temp_tables_for_destruction
FROM sys.dm_os_performance_counters AS p
WHERE RTRIM(p.object_name) LIKE N'%:General Statistics'
  AND RTRIM(p.counter_name) = N'Temp Tables Creation Rate';

-- 3. The version store, per database: the row versions that row versioning keeps in
--    tempdb (RCSI is on in PachadataTraining, but the portal only reads).
SELECT DB_NAME(database_id) AS database_name, reserved_page_count / 128.0 AS version_store_mb
FROM sys.dm_tran_version_store_space_usage
WHERE reserved_page_count > 0;
SELECT COUNT(*) AS databases_with_versions
FROM sys.dm_tran_version_store_space_usage
WHERE reserved_page_count > 0;
