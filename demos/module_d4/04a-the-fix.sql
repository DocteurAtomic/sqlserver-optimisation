-- Clip D4.4: the fix in the procedure. Runs on the lab, in one session, while charge.sh runs
-- (it also runs alone). Then 02b-measure-load.sql measures one minute of the portal.
-- The problem of the module: the CREATE INDEX that follows the CREATE TABLE. A temporary
-- table created in a procedure can be cached by SQL Server between two calls: at the end of
-- the call, the table is emptied and renamed instead of dropped, and the next call takes it
-- back. A DDL statement on the table after its creation (here CREATE INDEX) prevents it.
-- The index declared in the CREATE TABLE gives the same table, and lets it be cached.
USE PachadataTraining;
SET NOCOUNT ON;
GO
CREATE OR ALTER PROCEDURE Course.GetAttendanceSheet
    @SessionId int
AS
SET NOCOUNT ON;
CREATE TABLE #Sheet (
    EnrollmentId int NOT NULL,
    ContactId int NULL,
    LastName varchar(50) NULL,
    FirstName varchar(50) NULL,
    Attended bit NOT NULL,
    INDEX cx_Sheet CLUSTERED (LastName, FirstName)
);
INSERT INTO #Sheet (EnrollmentId, ContactId, LastName, FirstName, Attended)
SELECT e.EnrollmentId, e.ContactId, c.LastName, c.FirstName, e.Attended
FROM Enrollment.Enrollment AS e
LEFT JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
WHERE e.SessionId = @SessionId
  AND e.CancellationDate IS NULL;
SELECT EnrollmentId, LastName, FirstName, Attended
FROM #Sheet
ORDER BY LastName, FirstName;
GO
-- Ten seconds of the counter: temporary tables really created by the instance.
DECLARE @c0 bigint, @t0 datetime2 = SYSDATETIME();
SELECT @c0 = cntr_value
FROM sys.dm_os_performance_counters
WHERE RTRIM(object_name) LIKE N'%:General Statistics'
  AND RTRIM(counter_name) = N'Temp Tables Creation Rate';
WAITFOR DELAY '00:00:10';
SELECT CAST((cntr_value - @c0) / (DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0) AS decimal(9, 0)) AS temp_tables_created_per_s
FROM sys.dm_os_performance_counters
WHERE RTRIM(object_name) LIKE N'%:General Statistics'
  AND RTRIM(counter_name) = N'Temp Tables Creation Rate';
-- The cached tables: a dropped temporary table that SQL Server keeps is renamed # followed
-- by eight hexadecimal digits.
SELECT COUNT(*) AS cached_temp_tables
FROM tempdb.sys.tables
WHERE name LIKE N'#[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]';
