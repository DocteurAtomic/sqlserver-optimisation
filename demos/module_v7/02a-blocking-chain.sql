-- Module V7, clip 2: finding a blocking chain. Runs on the lab, in one session, while
-- ./demos/module_v7/charge.sh is running (after 00-setup.sql).
-- ci: skip (it needs the load: without it, every step returns no rows)
-- It only reads dynamic management views.
USE PachadataTraining;
GO
SET NOCOUNT ON;
GO
-- Step 1. The requests that wait for another session, and what they wait for.
SELECT r.session_id, s.host_name, r.command, r.wait_type, r.wait_time AS wait_ms,
       r.blocking_session_id, r.wait_resource
FROM sys.dm_exec_requests AS r
JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
WHERE r.blocking_session_id <> 0
ORDER BY r.wait_time DESC;
GO
-- Step 2. The chain: from each head blocker (it blocks others and waits for nobody) down
-- to the sessions that wait behind it, level by level.
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
SELECT c.level, c.path, c.wait_type, c.wait_time AS wait_ms,
       LEFT(REPLACE(REPLACE(t.text, CHAR(13), ' '), CHAR(10), ' '), 60) AS running_text
FROM Chain AS c
OUTER APPLY sys.dm_exec_sql_text(c.sql_handle) AS t
ORDER BY c.path;
GO
-- Step 3. The head blocker: what it was sent, how long its transaction has been open, and
-- the locks it holds in the base.
DECLARE @head int = (
    SELECT TOP (1) r.blocking_session_id
    FROM sys.dm_exec_requests AS r
    WHERE r.blocking_session_id <> 0
      AND NOT EXISTS (SELECT 1 FROM sys.dm_exec_requests AS h
                      WHERE h.session_id = r.blocking_session_id AND h.blocking_session_id <> 0)
    ORDER BY r.wait_time DESC);

SELECT @head AS head_session, s.host_name, ib.event_info AS input_buffer
FROM sys.dm_exec_sessions AS s
CROSS APPLY sys.dm_exec_input_buffer(s.session_id, NULL) AS ib
WHERE s.session_id = @head;

SELECT st.session_id, at.transaction_begin_time,
       DATEDIFF(millisecond, at.transaction_begin_time, SYSDATETIME()) AS open_ms,
       r.wait_type AS head_waits_on
FROM sys.dm_tran_session_transactions AS st
JOIN sys.dm_tran_active_transactions AS at ON at.transaction_id = st.transaction_id
LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = st.session_id
WHERE st.session_id = @head;

SELECT tl.resource_type, tl.request_mode, tl.request_status, COUNT(*) AS locks
FROM sys.dm_tran_locks AS tl
WHERE tl.request_session_id = @head AND tl.resource_database_id = DB_ID()
GROUP BY tl.resource_type, tl.request_mode, tl.request_status
ORDER BY tl.resource_type;
GO
-- Step 4. What the sessions of the load have waited for since they connected.
SELECT s.host_name, ws.wait_type, ws.waiting_tasks_count, ws.wait_time_ms,
       ws.wait_time_ms / NULLIF(ws.waiting_tasks_count, 0) AS avg_wait_ms
FROM sys.dm_exec_session_wait_stats AS ws
JOIN sys.dm_exec_sessions AS s ON s.session_id = ws.session_id
WHERE (s.host_name LIKE N'billing-%' OR s.host_name LIKE N'reminders-%' OR s.host_name LIKE N'web-%')
  AND ws.wait_type LIKE N'LCK_M_%'
ORDER BY s.host_name, ws.wait_time_ms DESC;
GO
