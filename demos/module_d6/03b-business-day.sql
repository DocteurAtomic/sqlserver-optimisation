-- Clip D6.3: a short working day on the database, then what the index views say about it.
-- Runs on the lab, in one session, after 03a-usage-since.sql. Reads only. Lasts about ten
-- seconds: the reports of the accounting and marketing teams, three times each.
USE PachadataTraining;
SET NOCOUNT ON;
GO
EXEC Report.CampaignPerformance @Start = '20260101', @End = '20260630';
EXEC Report.RecipientsByCampaign @CampaignId = 1001;
EXEC Report.MonthlyRevenue @Start = '20250101', @End = '20251231';
EXEC Report.OverduePayments;
EXEC Report.SessionFillRate @Year = 2025;
EXEC Marketing.GetLetterResults @CampaignId = 36;
EXEC Marketing.GetLetterResults @CampaignId = 17391;
GO 3
-- 1. Every nonclustered index of the database, with what the day did to it. An index never
--    touched has no row in the view: the LEFT JOIN keeps it, with NULL counters.
SELECT OBJECT_SCHEMA_NAME(i.object_id) + N'.' + OBJECT_NAME(i.object_id) AS TableName,
       i.name AS IndexName, i.is_unique, i.is_unique_constraint,
       u.user_seeks, u.user_scans, u.user_lookups, u.user_updates
FROM sys.indexes AS i
JOIN sys.objects AS o ON o.object_id = i.object_id AND o.type = 'U' AND o.is_ms_shipped = 0
LEFT JOIN sys.dm_db_index_usage_stats AS u
    ON u.database_id = DB_ID() AND u.object_id = i.object_id AND u.index_id = i.index_id
WHERE i.type = 2
ORDER BY ISNULL(u.user_seeks + u.user_scans + u.user_lookups, 0), TableName, IndexName;
GO
-- 2. The suggestions of missing indexes, by score: seeks x average cost x expected gain.
SELECT OBJECT_SCHEMA_NAME(d.object_id) + N'.' + OBJECT_NAME(d.object_id) AS TableName,
       d.equality_columns, d.inequality_columns, d.included_columns, s.user_seeks,
       CAST(s.avg_total_user_cost AS decimal(9, 2)) AS AvgCost,
       CAST(s.avg_user_impact AS decimal(5, 1)) AS GainPct,
       CAST(s.user_seeks * s.avg_total_user_cost * s.avg_user_impact / 100 AS decimal(12, 1)) AS Score
FROM sys.dm_db_missing_index_details AS d
JOIN sys.dm_db_missing_index_groups AS g ON g.index_handle = d.index_handle
JOIN sys.dm_db_missing_index_group_stats AS s ON s.group_handle = g.index_group_handle
WHERE d.database_id = DB_ID()
ORDER BY Score DESC;
GO
-- 3. The statement behind each suggestion on Marketing.Delivery (SQL Server 2019 and later).
SELECT d.equality_columns, d.included_columns, q.user_seeks,
       LEFT(t.text, 120) AS StatementStart
FROM sys.dm_db_missing_index_details AS d
JOIN sys.dm_db_missing_index_groups AS g ON g.index_handle = d.index_handle
JOIN sys.dm_db_missing_index_group_stats_query AS q ON q.group_handle = g.index_group_handle
CROSS APPLY sys.dm_exec_sql_text(q.last_sql_handle) AS t
WHERE d.database_id = DB_ID() AND d.object_id = OBJECT_ID(N'Marketing.Delivery');
GO
