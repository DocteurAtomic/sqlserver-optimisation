-- Module D4, setup. Runs in one session on the lab, before the first clip of the module.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. The problem of the module: Course.GetAttendanceSheet, the procedure behind the
--    attendance sheet of the trainers' portal, builds the sheet in a temporary table, then
--    creates its clustered index with a CREATE INDEX after the CREATE TABLE. A DDL statement
--    on the temporary table after its creation stops SQL Server from caching the table
--    between calls: every call creates a new table in the catalog of tempdb, and drops it.
--    Under twenty concurrent sessions (./demos/module_d4/charge.sh), the sessions wait on
--    the pages of the catalog of tempdb. Clip D4.4 declares the index in the CREATE TABLE.
-- 00b-presize-tempdb.sql follows: it preallocates the files of tempdb before the load.
-- The video plays the module on a throwaway copy of the lab (container sqlopt-d4): clip
-- D4.2 adds files to tempdb and clip D4.3 changes a server configuration that needs a
-- restart. On your lab, play 99-cleanup.sql at the end of the module.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
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
    Attended bit NOT NULL
);
INSERT INTO #Sheet (EnrollmentId, ContactId, LastName, FirstName, Attended)
SELECT e.EnrollmentId, e.ContactId, c.LastName, c.FirstName, e.Attended
FROM Enrollment.Enrollment AS e
LEFT JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
WHERE e.SessionId = @SessionId
  AND e.CancellationDate IS NULL;
CREATE CLUSTERED INDEX cx_Sheet ON #Sheet (LastName, FirstName);
SELECT EnrollmentId, LastName, FirstName, Attended
FROM #Sheet
ORDER BY LastName, FirstName;
GO
-- The attendance sheet of session 12000, and the state of tempdb on the lab.
EXEC Course.GetAttendanceSheet @SessionId = 12000;
SELECT SERVERPROPERTY('IsTempdbMetadataMemoryOptimized') AS memory_optimized_metadata,
       (SELECT COUNT(*) FROM tempdb.sys.database_files WHERE type_desc = N'ROWS') AS tempdb_data_files;
