-- Clip 4.1: what Query Store keeps, and how it is set. Runs on the lab, in one session.
-- The settings are only read here; times are in UTC.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- The settings of the database. The delivered backup has a one-minute interval and captures
-- every query, for the course; the defaults are 60 minutes and AUTO.
SELECT actual_state_desc, desired_state_desc, readonly_reason,
       current_storage_size_mb, max_storage_size_mb,
       interval_length_minutes, flush_interval_seconds,
       query_capture_mode_desc, size_based_cleanup_mode_desc,
       stale_query_threshold_days, max_plans_per_query
FROM sys.database_query_store_options;
GO
-- What it holds: texts, queries, plans, intervals, and statistics per plan and interval.
SELECT (SELECT COUNT(*) FROM sys.query_store_query_text) AS query_texts,
       (SELECT COUNT(*) FROM sys.query_store_query) AS queries,
       (SELECT COUNT(*) FROM sys.query_store_plan) AS plans,
       (SELECT COUNT(*) FROM sys.query_store_runtime_stats_interval) AS intervals,
       (SELECT COUNT(*) FROM sys.query_store_runtime_stats) AS runtime_stats_rows,
       (SELECT COUNT(*) FROM sys.query_store_wait_stats) AS wait_stats_rows;
GO
-- The query of the procedure: its text, as Query Store stores it.
SELECT q.query_id, q.object_id, OBJECT_NAME(q.object_id) AS module_name,
       q.count_compiles, qt.query_sql_text
FROM sys.query_store_query AS q
JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName');
GO
-- A query is visible as soon as it has run, before any write to disk: the views read the
-- memory and the disk together. Its text is normalized: the literal becomes a parameter
-- (simple parameterization), and the comment after the statement is dropped. Three dates,
-- one query, one row of statistics for the interval.
SELECT COUNT(*) AS InvoicesSince FROM Enrollment.Invoice WHERE InvoiceDate >= '20260101' /* back office */;
SELECT COUNT(*) AS InvoicesSince FROM Enrollment.Invoice WHERE InvoiceDate >= '20250101' /* back office */;
SELECT COUNT(*) AS InvoicesSince FROM Enrollment.Invoice WHERE InvoiceDate >= '20200101' /* back office */;
-- In my tests, a new query sometimes took a second or two to show: the script waits.
WAITFOR DELAY '00:00:02';
SELECT q.query_id, i.start_time, rs.count_executions,
       CAST(rs.avg_logical_io_reads AS int) AS avg_reads,
       rs.min_logical_io_reads AS min_reads, rs.max_logical_io_reads AS max_reads,
       qt.query_sql_text
FROM sys.query_store_query_text AS qt
JOIN sys.query_store_query AS q ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan AS p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
WHERE qt.query_sql_text LIKE N'%InvoicesSince%'
  AND qt.query_sql_text NOT LIKE N'%query[_]store%';
