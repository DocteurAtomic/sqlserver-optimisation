-- Module D5, setup. Runs in one session on a throwaway container (the video: sqlopt-d5),
-- before the first clip of the module.
-- ci: skip (it creates two logins on the instance; the module changes the resource governor)
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. The problem of the module: two applications share the instance, and nothing separates
--    them. The reporting tool connects as report_user and runs the heavy reports of the
--    Report schema, several at a time, each one in parallel. The enrollment screen of the
--    back office connects as entry_user and records enrollments, one short call at a time.
--    The resource governor is off, as on every new instance: both logins land in the
--    default workload group, and the reports take the processors the enrollments need.
--    charge.sh starts both applications; clip D5.1 measures the enrollment screen.
-- 3. dbo.EntryTiming keeps the duration of each enrollment, as the screen measures it.
--    The screen rolls each enrollment back after the call (a lab choice: the data stay the
--    same from one run to the next), so the table is the only thing the load writes.
-- The logins are instance objects, which a restore does not remove: 99-cleanup.sql drops
-- them, with the resource governor configuration of the module.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
-- The two logins of the applications. The passwords are those of the lab, written here on
-- purpose: charge.sh connects with them.
DECLARE @k nvarchar(max) = N'';
SELECT @k += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; '
FROM sys.dm_exec_sessions
WHERE login_name IN (N'report_user', N'entry_user');
EXEC (@k);
IF SUSER_ID(N'report_user') IS NOT NULL DROP LOGIN report_user;
IF SUSER_ID(N'entry_user') IS NOT NULL DROP LOGIN entry_user;
CREATE LOGIN report_user WITH PASSWORD = N'Lab#Reading2026', DEFAULT_DATABASE = PachadataTraining;
CREATE LOGIN entry_user WITH PASSWORD = N'Lab#Typing2026', DEFAULT_DATABASE = PachadataTraining;
GO
USE PachadataTraining;
GO
CREATE TABLE dbo.EntryTiming (
    CallId     int IDENTITY PRIMARY KEY,
    CalledAt   datetime2(3) NOT NULL DEFAULT SYSDATETIME(),
    DurationMs decimal(9, 3) NOT NULL
);
CREATE USER report_user FOR LOGIN report_user;
CREATE USER entry_user FOR LOGIN entry_user;
GRANT EXECUTE ON SCHEMA::Report TO report_user;
GRANT EXECUTE ON OBJECT::Enrollment.EnrollTrainee TO entry_user;
GRANT INSERT ON OBJECT::dbo.EntryTiming TO entry_user;
GO
-- The state of the resource governor on the lab: no classifier function, governor off,
-- the two built-in pools and groups only.
SELECT OBJECT_NAME(classifier_function_id) AS classifier_function, is_enabled
FROM sys.resource_governor_configuration;
SELECT name AS login_name, default_database_name
FROM sys.server_principals
WHERE name IN (N'report_user', N'entry_user');
