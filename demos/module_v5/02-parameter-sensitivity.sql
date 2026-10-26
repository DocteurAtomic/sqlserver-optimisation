-- Clip V5.2: the parameter sensitivity. Two kinds of campaigns in one column, the histogram
-- that tells them apart, the value the plan was compiled for, then the plan of each kind
-- applied to the other, measured. Runs on the lab, in one session, after 01-plan-cache.sql.
-- The calls run with the options of the application (ARITHABORT OFF). Turn on the actual
-- plan in SSMS (Ctrl+M) for the calls of steps 3 and 5. The loops of step 6 last about
-- twenty seconds; their rows go to a temporary table.
USE PachadataTraining;
GO
SET NOCOUNT ON;
SET ARITHABORT OFF;
GO
-- 1. The campaigns: thousands of small evaluations, a few dozen monthly letters.
SELECT c.CampaignType, COUNT(*) AS Campaigns,
       MIN(d.Deliveries) AS MinDeliveries, MAX(d.Deliveries) AS MaxDeliveries
FROM Marketing.Campaign AS c
JOIN (SELECT CampaignId, COUNT(*) AS Deliveries
      FROM Marketing.Delivery GROUP BY CampaignId) AS d ON d.CampaignId = c.CampaignId
GROUP BY c.CampaignType;
GO
-- 2. The histogram of the index on CampaignId: one step per letter, and the evaluations.
SELECT h.step_number, h.range_high_key, h.equal_rows, h.range_rows, h.average_range_rows
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_histogram(s.object_id, s.stats_id) AS h
WHERE s.object_id = OBJECT_ID(N'Marketing.Delivery')
  AND s.name = N'ix_Delivery_CampaignId'
  AND (h.range_high_key IN (35, 36, 1038) OR h.range_high_key >= 17388);
GO
-- 3. The morning of the tool: the letter first, then one evaluation.
SET STATISTICS IO, TIME ON;
EXEC Report.RecipientsByCampaign @CampaignId = 36;
EXEC Report.RecipientsByCampaign @CampaignId = 17389;
SET STATISTICS IO, TIME OFF;
GO
-- 4. The value the cached plan was compiled for. The actual plan of step 3 gives both,
--    ParameterCompiledValue and ParameterRuntimeValue, in the Parameter List of the SELECT.
--    The plan of SSMS (ARITHABORT ON), compiled in clip V5.1, is still there.
WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')
SELECT CASE WHEN CAST(pa.value AS int) & 4096 = 4096 THEN 'ON' ELSE 'OFF' END AS ArithAbort,
       ps.execution_count,
       pr.n.value('@Column', 'sysname') AS ParameterName,
       pr.n.value('@ParameterCompiledValue', 'nvarchar(50)') AS CompiledValue
FROM sys.dm_exec_procedure_stats AS ps
CROSS APPLY sys.dm_exec_plan_attributes(ps.plan_handle) AS pa
CROSS APPLY sys.dm_exec_query_plan(ps.plan_handle) AS qp
CROSS APPLY qp.query_plan.nodes('//ParameterList/ColumnReference') AS pr(n)
WHERE ps.database_id = DB_ID() AND ps.object_id = OBJECT_ID(N'Report.RecipientsByCampaign')
  AND pa.attribute = N'set_options';
GO
-- 5. The other order: the evaluation compiles, then the letter.
EXEC sys.sp_recompile N'Report.RecipientsByCampaign';
GO
SET STATISTICS IO, TIME ON;
EXEC Report.RecipientsByCampaign @CampaignId = 17389;
EXEC Report.RecipientsByCampaign @CampaignId = 36;
SET STATISTICS IO, TIME OFF;
GO
-- 6. A morning of the sender: one hundred evaluations, first with the plan of the letter,
--    then with the plan of an evaluation.
CREATE TABLE #Recipients (LastName varchar(50), FirstName varchar(50), Email varchar(150),
                          SendDate datetime2, Opened bit);
GO
EXEC sys.sp_recompile N'Report.RecipientsByCampaign';
GO
INSERT INTO #Recipients EXEC Report.RecipientsByCampaign @CampaignId = 36;
GO
DECLARE @Start datetime2 = SYSDATETIME(),
        @Cpu int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID),
        @CampaignId int = 17291;
WHILE @CampaignId <= 17390
BEGIN
    INSERT INTO #Recipients EXEC Report.RecipientsByCampaign @CampaignId = @CampaignId;
    SET @CampaignId += 1;
END;
SELECT 'plan of the letter' AS CompiledFor,
       DATEDIFF(millisecond, @Start, SYSDATETIME()) AS ElapsedMs,
       (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID) - @Cpu AS CpuMs;
GO
EXEC sys.sp_recompile N'Report.RecipientsByCampaign';
GO
DECLARE @Start datetime2 = SYSDATETIME(),
        @Cpu int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID),
        @CampaignId int = 17291;
WHILE @CampaignId <= 17390
BEGIN
    INSERT INTO #Recipients EXEC Report.RecipientsByCampaign @CampaignId = @CampaignId;
    SET @CampaignId += 1;
END;
SELECT 'plan of an evaluation' AS CompiledFor,
       DATEDIFF(millisecond, @Start, SYSDATETIME()) AS ElapsedMs,
       (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID) - @Cpu AS CpuMs;
GO
DROP TABLE #Recipients;
GO
