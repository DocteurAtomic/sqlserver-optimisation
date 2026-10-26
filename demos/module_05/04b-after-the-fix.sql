-- ci: skip (run after charge.sh has run again for two minutes, after 04a-the-fix.sql)
-- Clip 5.4: the deadlocks of the database in system_health, before and after the change of
-- Enrollment.SendJoiningInstructions. Runs on the lab, in one session.
USE PachadataTraining;
GO
SET NOCOUNT ON;
GO
-- Reading a target of sys.dm_xe_session_targets flushes the buffers of every session of the
-- instance to their targets: system_health has nothing left in memory after this query.
SELECT s.name, t.target_name, t.execution_count
FROM sys.dm_xe_sessions AS s
JOIN sys.dm_xe_session_targets AS t ON t.event_session_address = s.address
WHERE s.name = N'system_health';
GO
-- The deadlocks that involve the database since 00-setup.sql created Course.ChangeRoom,
-- before and after Enrollment.SendJoiningInstructions was altered (create_date and
-- modify_date are local time; the file gives UTC).
DECLARE @since_utc datetime2 = (
    SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, SYSDATETIME(), SYSUTCDATETIME()), create_date)
    FROM sys.objects
    WHERE object_id = OBJECT_ID(N'Course.ChangeRoom'));
DECLARE @fixed_utc datetime2 = (
    SELECT DATEADD(MINUTE, DATEDIFF(MINUTE, SYSDATETIME(), SYSUTCDATETIME()), modify_date)
    FROM sys.procedures
    WHERE object_id = OBJECT_ID(N'Enrollment.SendJoiningInstructions'));

WITH reports AS (
    SELECT timestamp_utc
    FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
    WHERE object_name = N'xml_deadlock_report'
      AND timestamp_utc > @since_utc
      AND CAST(event_data AS xml).exist('//process[@currentdbname = "PachadataTraining"]') = 1
)
SELECT CASE WHEN timestamp_utc < @fixed_utc THEN '1. before the fix' ELSE '2. after the fix' END AS period,
       COUNT(*) AS deadlocks, MIN(timestamp_utc) AS first_utc, MAX(timestamp_utc) AS last_utc
FROM reports
GROUP BY CASE WHEN timestamp_utc < @fixed_utc THEN '1. before the fix' ELSE '2. after the fix' END
UNION ALL
SELECT '2. after the fix', 0, NULL, NULL
WHERE NOT EXISTS (SELECT 1 FROM reports WHERE timestamp_utc >= @fixed_utc)
ORDER BY period;

SELECT @since_utc AS since_utc, @fixed_utc AS fixed_utc, SYSUTCDATETIME() AS now_utc;
GO
