-- Clip D2.1: measuring I/O on an interval. Runs on the lab, in one session, after
-- 00-setup.sql. The nightly job updates the 1.4 million videos watched of the e-learning
-- activity in one statement (a stand-in for the job that recomputes their duration); it
-- takes about half a minute on the lab.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. What sys.dm_io_virtual_file_stats has accumulated since the instance started, for the
--    files of this database: everything that happened, mixed together.
SELECT mf.name AS file_name, mf.type_desc,
       vf.num_of_reads, vf.num_of_writes,
       vf.io_stall_read_ms / NULLIF(vf.num_of_reads, 0) AS ms_per_read,
       vf.io_stall_write_ms / NULLIF(vf.num_of_writes, 0) AS ms_per_write
FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL) AS vf
JOIN sys.database_files AS mf ON mf.file_id = vf.file_id;
GO
-- 2. A snapshot of the counters, then the nightly job, then the difference: what this interval did.
DROP TABLE IF EXISTS #io_before, #waits_before;
SELECT file_id, num_of_reads, num_of_bytes_read, io_stall_read_ms,
       num_of_writes, num_of_bytes_written, io_stall_write_ms
INTO #io_before
FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL);
SELECT wait_type, waiting_tasks_count, wait_time_ms
INTO #waits_before
FROM sys.dm_exec_session_wait_stats
WHERE session_id = @@SPID;

DECLARE @start datetime2 = SYSDATETIME();
UPDATE Elearning.Activity
SET DurationSeconds = DurationSeconds + 1
WHERE EventTypeCode = 'VIDE';
SELECT DATEDIFF(MILLISECOND, @start, SYSDATETIME()) AS job_ms;

SELECT mf.name AS file_name,
       v.num_of_reads - b.num_of_reads AS reads,
       (v.num_of_bytes_read - b.num_of_bytes_read) / 1048576 AS read_mb,
       v.num_of_writes - b.num_of_writes AS writes,
       (v.num_of_bytes_written - b.num_of_bytes_written) / 1048576 AS written_mb,
       (v.num_of_bytes_written - b.num_of_bytes_written) / 1024
            / NULLIF(v.num_of_writes - b.num_of_writes, 0) AS kb_per_write,
       CAST((v.io_stall_write_ms - b.io_stall_write_ms) * 1.0
            / NULLIF(v.num_of_writes - b.num_of_writes, 0) AS decimal(10, 2)) AS ms_per_write
FROM sys.dm_io_virtual_file_stats(DB_ID(), NULL) AS v
JOIN #io_before AS b ON b.file_id = v.file_id
JOIN sys.database_files AS mf ON mf.file_id = v.file_id;

-- 3. What the session waited for during the job.
SELECT TOP (6) w.wait_type,
       w.waiting_tasks_count - ISNULL(b.waiting_tasks_count, 0) AS waits,
       w.wait_time_ms - ISNULL(b.wait_time_ms, 0) AS wait_ms
FROM sys.dm_exec_session_wait_stats AS w
LEFT JOIN #waits_before AS b ON b.wait_type = w.wait_type
WHERE w.session_id = @@SPID
ORDER BY wait_ms DESC;
GO
