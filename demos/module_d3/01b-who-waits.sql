-- Clip D3.1: who waits on the journal? Runs on the lab, in one session, while charge.sh runs
-- (alone, the first query returns no row).
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The waits of the website sessions, added up since each one connected.
--    sys.dm_exec_session_wait_stats keeps one row per session and per wait type.
SELECT TOP (6) w.wait_type, SUM(w.waiting_tasks_count) AS waits, SUM(w.wait_time_ms) AS wait_ms
FROM sys.dm_exec_session_wait_stats AS w
JOIN sys.dm_exec_sessions AS s ON s.session_id = w.session_id
WHERE s.host_name LIKE N'website-%'
GROUP BY w.wait_type
ORDER BY wait_ms DESC;

-- 2. The Query Store of the base: its capture mode, its state, and the number of queries it
--    has recorded. readonly_reason 262144: the in-memory items waiting to be written to
--    disk reached their limit, and the store stops collecting until they are written.
SELECT query_capture_mode_desc, desired_state_desc, actual_state_desc, readonly_reason,
       current_storage_size_mb
FROM sys.database_query_store_options;
SELECT COUNT(*) AS queries_in_query_store
FROM sys.query_store_query;
