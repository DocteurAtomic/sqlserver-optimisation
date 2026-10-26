-- Clip D2.3: the virtual log files. Runs on the lab, in one session, after
-- 01-io-interval.sql. It only reads.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. One row per VLF: how many, how big, how many active.
SELECT COUNT(*) AS vlf,
       CAST(SUM(vlf_size_mb) AS decimal(10, 1)) AS log_mb,
       CAST(MIN(vlf_size_mb) AS decimal(10, 2)) AS smallest_mb,
       CAST(MAX(vlf_size_mb) AS decimal(10, 2)) AS largest_mb,
       SUM(CAST(vlf_active AS int)) AS active
FROM sys.dm_db_log_info(DB_ID());

-- 2. The sizes of the VLFs, from the start of the file: the first ones come from the shrunk
--    file, then one VLF per growth of 1 MB.
SELECT CAST(vlf_size_mb AS decimal(10, 2)) AS vlf_size_mb, COUNT(*) AS vlf
FROM sys.dm_db_log_info(DB_ID())
GROUP BY CAST(vlf_size_mb AS decimal(10, 2))
ORDER BY vlf_size_mb;

-- 3. The summary of the log.
SELECT total_vlf_count, active_vlf_count,
       CAST(total_log_size_mb AS decimal(10, 1)) AS total_log_mb,
       CAST(active_log_size_mb AS decimal(10, 1)) AS active_log_mb
FROM sys.dm_db_log_stats(DB_ID());
GO
