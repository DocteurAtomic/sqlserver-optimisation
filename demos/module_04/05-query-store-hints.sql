-- Clip 4.5: a Query Store hint instead of a forced plan, then the sabotage revealed. Runs on
-- the lab, in one session, after 04b-forcing-that-fails.sql. The hint is removed and the
-- plan forced again at the end: the correction of the module stays in place.
USE PachadataTraining;
SET NOCOUNT ON;
SET ARITHABORT ON;  -- as in SSMS and in 00-setup.sql
GO
-- The forcing removed: the query is free again.
DECLARE @query_id bigint, @plan_id bigint;
SELECT @query_id = p.query_id, @plan_id = p.plan_id
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName') AND p.is_forced_plan = 1;
EXEC sys.sp_query_store_unforce_plan @query_id = @query_id, @plan_id = @plan_id;

-- A hint on the query, without touching the code of the procedure: RECOMPILE, a plan built
-- for each value received.
EXEC sys.sp_query_store_set_hints @query_id = @query_id, @query_hints = N'OPTION (RECOMPILE)';
SELECT query_hint_id, query_id, query_hint_text, source_desc,
       query_hint_failure_count, last_query_hint_failure_reason_desc
FROM sys.query_store_query_hints;
GO
SET STATISTICS IO ON;
EXEC Contact.GetContactByName @LastName = N'Simon';
EXEC Contact.GetContactByName @LastName = N'Arsac';
SET STATISTICS IO OFF;
GO
WAITFOR DELAY '00:00:02';  -- a new plan can take a second or two to show
-- What RECOMPILE costs: a compilation at each call, counted by Query Store.
SELECT p.plan_id, p.count_compiles, p.is_forced_plan
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
ORDER BY p.plan_id;
GO
-- The hint removed, the plan of the healthy period forced again.
DECLARE @query_id bigint = (SELECT query_id FROM sys.query_store_query
                            WHERE object_id = OBJECT_ID(N'Contact.GetContactByName'));
EXEC sys.sp_query_store_clear_hints @query_id = @query_id;
DECLARE @plan_id bigint = (
    SELECT TOP (1) p.plan_id
    FROM sys.query_store_plan AS p
    JOIN sys.query_store_runtime_stats AS rs ON rs.plan_id = p.plan_id
    WHERE p.query_id = @query_id
    GROUP BY p.plan_id
    ORDER BY SUM(rs.avg_logical_io_reads * rs.count_executions) / SUM(rs.count_executions));
EXEC sys.sp_query_store_force_plan @query_id = @query_id, @plan_id = @plan_id;
SELECT COUNT(*) AS hints_left FROM sys.query_store_query_hints;
SELECT plan_id, is_forced_plan FROM sys.query_store_plan WHERE query_id = @query_id ORDER BY plan_id;
GO
-- The sabotage: a recompilation at the wrong moment, then an atypical first call. PSP is on
-- (its default at level 170), and did not prevent it.
SELECT name, value, is_value_default
FROM sys.database_scoped_configurations
WHERE name IN (N'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION', N'OPTIMIZED_PLAN_FORCING');
-- PSP would have stored a dispatcher plan and its variants: the plans are ordinary ones.
SELECT p.plan_id, p.plan_type_desc
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
ORDER BY p.plan_id;
GO
-- The measure of the correction: the calls of the regressed period replayed with the plan
-- forced, after the same recompilation and the same first call for Simon.
EXEC sys.sp_recompile N'Contact.GetContactByName';
GO
SET STATISTICS IO ON;
EXEC Contact.GetContactByName @LastName = N'Simon';
EXEC Contact.GetContactByName @LastName = N'Arsac';
EXEC Contact.GetContactByName @LastName = N'Martin';
SET STATISTICS IO OFF;
