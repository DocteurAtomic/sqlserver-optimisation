-- Clip D7.2, the blocking, seen while it lasts. Runs on the lab, in one session, after
-- charge.sh has played the night, while accounting-ssms and payments-import still run.
-- ci: skip (it needs the sessions the night leaves: without them, every step returns no rows)
-- It only reads dynamic management views. The queries are those of module V7.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- Step 1. The requests that wait for another session.
SELECT r.session_id, s.host_name, r.command, r.wait_type, r.wait_time / 1000 AS wait_s,
       r.blocking_session_id, r.wait_resource
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
WHERE r.blocking_session_id <> 0
ORDER BY r.wait_time DESC;
GO
-- Step 2. The chain, from the head blocker down (module V7, clip 2).
WITH Blocking AS (
    SELECT s.session_id,
           ISNULL(r.blocking_session_id, 0) AS blocking_session_id,
           s.host_name, r.wait_type, r.wait_time, r.sql_handle
    FROM sys.dm_exec_sessions AS s
    LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
    WHERE s.is_user_process = 1
),
Chain AS (
    SELECT b.session_id, b.blocking_session_id, b.host_name, b.wait_type, b.wait_time,
           b.sql_handle, 0 AS level,
           CAST(CONCAT(b.host_name, ' (', b.session_id, ')') AS varchar(400)) AS path
    FROM Blocking AS b
    WHERE b.blocking_session_id = 0
      AND EXISTS (SELECT 1 FROM Blocking AS w WHERE w.blocking_session_id = b.session_id)
    UNION ALL
    SELECT b.session_id, b.blocking_session_id, b.host_name, b.wait_type, b.wait_time,
           b.sql_handle, c.level + 1,
           CAST(CONCAT(c.path, ' <- ', b.host_name, ' (', b.session_id, ')') AS varchar(400))
    FROM Blocking AS b
    JOIN Chain AS c ON b.blocking_session_id = c.session_id
)
SELECT c.level, c.path, c.wait_type, c.wait_time / 1000 AS wait_s,
       LEFT(REPLACE(REPLACE(t.text, CHAR(13), ' '), CHAR(10), ' '), 50) AS running_text
FROM Chain AS c
OUTER APPLY sys.dm_exec_sql_text(c.sql_handle) AS t
ORDER BY c.path;
GO
-- Step 3. The head: a session that runs nothing ("sleeping") and keeps a transaction open.
-- Its input buffer is the last batch it received; its locks in the base.
DECLARE @head int = (
    SELECT TOP (1) r.blocking_session_id
    FROM sys.dm_exec_requests AS r
    WHERE r.blocking_session_id <> 0
      AND NOT EXISTS (SELECT 1 FROM sys.dm_exec_requests AS h
                      WHERE h.session_id = r.blocking_session_id AND h.blocking_session_id <> 0)
    ORDER BY r.wait_time DESC);

SELECT s.session_id, s.host_name, s.program_name, s.status, s.open_transaction_count,
       s.last_request_end_time
FROM sys.dm_exec_sessions AS s
WHERE s.session_id = @head;

SELECT LEFT(REPLACE(REPLACE(ib.event_info, CHAR(13), ' '), CHAR(10), ' '), 110) AS input_buffer
FROM sys.dm_exec_input_buffer(@head, NULL) AS ib;

SELECT tl.resource_type, tl.request_mode, tl.request_status, COUNT(*) AS locks
FROM sys.dm_tran_locks AS tl
WHERE tl.request_session_id = @head AND tl.resource_database_id = DB_ID()
GROUP BY tl.resource_type, tl.request_mode, tl.request_status
ORDER BY tl.resource_type;
GO
