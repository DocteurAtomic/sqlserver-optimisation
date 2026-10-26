-- ci: skip (reads the load of charge.sh, which must be running)
-- Clips V2.1 and V2.4: what the page of the invoices of a company costs the server, measured
-- over 20 seconds while charge.sh sends it. Runs on the lab, in a session of its own, with
-- charge.sh started in a terminal. Reads only.
USE PachadataTraining;
GO
-- Two snapshots of the execution statistics of the procedure and of the use of the indexes
-- of Enrollment.Invoice, 20 seconds apart. The difference is what the page did meanwhile.
DECLARE @p1 TABLE (calls bigint, reads bigint, cpu_us bigint);
DECLARE @i1 TABLE (index_id int, seeks bigint, scans bigint, lookups bigint);
INSERT INTO @p1
SELECT SUM(execution_count), SUM(total_logical_reads), SUM(total_worker_time)
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Enrollment.GetCompanyInvoices');
INSERT INTO @i1
SELECT index_id, user_seeks, user_scans, user_lookups
FROM sys.dm_db_index_usage_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Enrollment.Invoice');

WAITFOR DELAY '00:00:20';

SELECT SUM(s.execution_count) - MAX(p.calls) AS Calls,
       (SUM(s.execution_count) - MAX(p.calls)) / 20 AS CallsPerSecond,
       (SUM(s.total_logical_reads) - MAX(p.reads))
           / NULLIF(SUM(s.execution_count) - MAX(p.calls), 0) AS ReadsPerCall,
       CAST((SUM(s.total_worker_time) - MAX(p.cpu_us)) / 1000.0 / 20 AS decimal(9, 1))
           AS CpuMsPerSecond
FROM sys.dm_exec_procedure_stats AS s
CROSS JOIN @p1 AS p
WHERE s.database_id = DB_ID() AND s.object_id = OBJECT_ID(N'Enrollment.GetCompanyInvoices');

SELECT i.name AS IndexName, u.user_seeks - b.seeks AS Seeks, u.user_scans - b.scans AS Scans,
       u.user_lookups - b.lookups AS Lookups
FROM sys.dm_db_index_usage_stats AS u
JOIN @i1 AS b ON b.index_id = u.index_id
JOIN sys.indexes AS i ON i.object_id = u.object_id AND i.index_id = u.index_id
WHERE u.database_id = DB_ID() AND u.object_id = OBJECT_ID(N'Enrollment.Invoice')
ORDER BY u.index_id;
GO
