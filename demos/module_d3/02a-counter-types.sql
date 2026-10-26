-- Clip D3.2: what sys.dm_os_performance_counters publishes, and what cntr_value contains.
-- Runs on the lab, in one session; it only reads.
USE master;
SET NOCOUNT ON;
GO
-- 1. The counters by type. cntr_type says how to read cntr_value.
SELECT cntr_type,
       CASE cntr_type
            WHEN 65792 THEN N'value at the time of reading'
            WHEN 272696576 THEN N'cumulative total: difference / seconds'
            WHEN 272696320 THEN N'cumulative total: difference / seconds'
            WHEN 537003264 THEN N'ratio: divide by its base'
            WHEN 1073939712 THEN N'base of a ratio or an average'
            WHEN 1073874176 THEN N'average: difference / difference of its base'
            ELSE N'other' END AS how_to_read,
       COUNT(*) AS counters,
       MIN(RTRIM(counter_name)) AS example
FROM sys.dm_os_performance_counters
GROUP BY cntr_type
ORDER BY counters DESC;

-- 2. The values are padded with spaces on the right: = finds the counter, LIKE without a
--    final wildcard does not.
SELECT N'=' AS test, COUNT(*) AS found
FROM sys.dm_os_performance_counters
WHERE counter_name = N'Page life expectancy'
UNION ALL
SELECT N'LIKE', COUNT(*)
FROM sys.dm_os_performance_counters
WHERE counter_name LIKE N'Page life expectancy';

-- 3. A ratio and its base: the hit ratio of the plan cache, since the start of the service.
SELECT RTRIM(r.instance_name) AS cache, r.cntr_value AS ratio_value, b.cntr_value AS base_value,
       CAST(100.0 * r.cntr_value / NULLIF(b.cntr_value, 0) AS decimal(5, 1)) AS hit_pct
FROM sys.dm_os_performance_counters AS r
JOIN sys.dm_os_performance_counters AS b
  ON b.object_name = r.object_name AND b.instance_name = r.instance_name
 AND b.counter_name = N'Cache Hit Ratio Base'
WHERE r.object_name LIKE N'%:Plan Cache%'
  AND r.counter_name = N'Cache Hit Ratio'
  AND r.instance_name IN (N'SQL Plans', N'Object Plans', N'_Total');

-- 4. Page life expectancy, for the whole buffer pool and per memory node.
SELECT RTRIM(object_name) AS object_name, RTRIM(instance_name) AS node, cntr_value AS seconds
FROM sys.dm_os_performance_counters
WHERE counter_name = N'Page life expectancy';
SELECT node_id, memory_node_id, online_scheduler_count
FROM sys.dm_os_nodes
WHERE node_state_desc NOT LIKE N'%DAC%';
