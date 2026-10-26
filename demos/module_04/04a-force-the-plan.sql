-- Clip 4.4: forcing the plan that worked, then measuring. Runs on the lab, in one session,
-- after 00-setup.sql. Messages of STATISTICS IO are in the Messages tab of SSMS.
USE PachadataTraining;
SET NOCOUNT ON;
SET ARITHABORT ON;  -- as in SSMS and in 00-setup.sql
GO
-- The plan to force: the one with the fewest reads on average. The identifiers are read,
-- not typed: they differ from one lab to another.
DECLARE @query_id bigint, @plan_id bigint;
SELECT TOP (1) @query_id = p.query_id, @plan_id = p.plan_id
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
GROUP BY p.query_id, p.plan_id
ORDER BY SUM(rs.avg_logical_io_reads * rs.count_executions) / SUM(rs.count_executions);
EXEC sys.sp_query_store_force_plan @query_id = @query_id, @plan_id = @plan_id;
SELECT @query_id AS query_id, @plan_id AS forced_plan_id;
GO
-- The same sequence as the sabotage: the plan thrown away, Simon first, then a rare name.
EXEC sys.sp_recompile N'Contact.GetContactByName';
GO
SET STATISTICS IO ON;
EXEC Contact.GetContactByName @LastName = N'Simon';
EXEC Contact.GetContactByName @LastName = N'Arsac';
SET STATISTICS IO OFF;
GO
WAITFOR DELAY '00:00:02';  -- a new plan can take a second or two to show
-- The state of the forcing. The forced plan is compiled again at each recompilation: the
-- result has the same shape, and may be stored under a new plan_id.
SELECT p.plan_id, p.is_forced_plan, p.plan_forcing_type_desc,
       p.force_failure_count, p.last_force_failure_reason_desc, p.count_compiles,
       p.query_plan_hash,
       CASE WHEN CAST(p.query_plan AS nvarchar(max)) LIKE N'%Lookup="1"%'
            THEN 'seek + key lookup' ELSE 'clustered index scan' END AS plan_shape,
       (SELECT SUM(rs.count_executions) FROM sys.query_store_runtime_stats AS rs
        WHERE rs.plan_id = p.plan_id) AS executions
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
ORDER BY p.plan_id;

SELECT reason, JSON_VALUE(state, '$.currentValue') AS state
FROM sys.dm_db_tuning_recommendations;
