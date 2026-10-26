-- Clip D7.3, automatic plan correction. Runs on the lab, in one session, right after
-- 00-setup.sql and before charge.sh: the option must be on before the regression happens.
-- Then charge.sh plays the night, and 01b-query-store.sql (step 4) and step 2 below show
-- what the engine did. FORCE_LAST_GOOD_PLAN is an option of the database: the next
-- 00-setup.sql restores the base without it.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- Step 1. Automatic tuning: the engine forces the last good plan of a query whose plan
-- regressed, then checks that the forced plan does better, and unforces it if not.
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);
SELECT name, desired_state_desc, actual_state_desc, reason_desc
FROM sys.database_automatic_tuning_options;
GO
-- Step 2, after the night. The recommendation, its state, and the plans of the query.
SELECT reason, score,
       JSON_VALUE(state, '$.currentValue') AS state,
       JSON_VALUE(state, '$.reason') AS state_reason,
       JSON_VALUE(details, '$.implementationDetails.script') AS script
FROM sys.dm_db_tuning_recommendations;
SELECT p.plan_id, p.is_forced_plan, p.plan_forcing_type_desc, p.last_execution_time
FROM sys.query_store_plan AS p
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
WHERE q.object_id = OBJECT_ID(N'Contact.GetContactByName')
ORDER BY p.plan_id;
GO
