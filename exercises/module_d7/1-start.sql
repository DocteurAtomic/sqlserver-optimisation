-- Module D7 exercise: another night on the PachaData server. Runs on the lab, in one session.
-- It lasts two to three minutes. Then 2a-window-1.sql and 2b-window-2.sql, in two windows.
-- Needs the database PachadataDBA of module 1 (demos/module_01/03a-baseline-tables.sql).
-- 1. Restores PachadataTraining as delivered, at compatibility level 170; Query Store with
--    one-minute intervals, emptied; the log at 128 MB, as in the demonstrations; the evening
--    snapshot of the baseline.
-- 2. Creates Enrollment.GetAttendanceSheet, the attendance sheet a trainer prints each
--    morning: the attendees of a session.
-- 3. Plays the evening: 300 attendance sheets.
-- 4. Plays the night. What it does is the subject of the exercise: read it after you have
--    run your routine (the answer is in 3-solution.sql).
USE master;
GO
IF DB_ID(N'PachadataDBA') IS NULL
    THROW 50000, N'PachadataDBA is missing: run demos/module_01/03a-baseline-tables.sql first.', 1;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
SET NOCOUNT ON;
ALTER DATABASE CURRENT SET QUERY_STORE (OPERATION_MODE = READ_WRITE,
    INTERVAL_LENGTH_MINUTES = 1, QUERY_CAPTURE_MODE = ALL);
ALTER DATABASE CURRENT SET QUERY_STORE CLEAR;
GO
USE PachadataTraining;
SET NOCOUNT ON;
CHECKPOINT;
DBCC SHRINKFILE (PachadataTraining_log, 128) WITH NO_INFOMSGS;
EXEC PachadataDBA.dbo.TakeSnapshot;
GO
CREATE OR ALTER PROCEDURE Enrollment.GetAttendanceSheet
    @SessionId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.LastName, c.FirstName, co.Name AS Company, e.WaitingList
    FROM Enrollment.Enrollment AS e
    JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
    LEFT JOIN Contact.Company AS co ON co.CompanyId = c.CompanyId
    WHERE e.SessionId = @SessionId
      AND e.CancellationDate IS NULL
    ORDER BY c.LastName, c.FirstName;
END;
GO
-- The evening: 300 sheets, sessions taken in order.
USE PachadataTraining;
SET NOCOUNT ON;
SET ARITHABORT ON;
CREATE TABLE #Sink (LastName varchar(50), FirstName varchar(50), Company varchar(100),
                    WaitingList bit);
DECLARE @i int = 0, @s int;
WHILE @i < 300
BEGIN
    SET @s = 9000 + @i * 7;
    INSERT #Sink EXEC Enrollment.GetAttendanceSheet @SessionId = @s;
    TRUNCATE TABLE #Sink;
    SET @i += 1;
END;
DROP TABLE #Sink;
-- Wait for the next one-minute interval of Query Store.
DECLARE @now datetime2 = SYSUTCDATETIME();
DECLARE @wait char(12) = CONVERT(char(12),
    DATEADD(millisecond, 61000 - DATEPART(second, @now) * 1000 - DATEPART(millisecond, @now),
            CAST('00:00:00' AS time)), 114);
WAITFOR DELAY @wait;
GO
-- The night.
USE PachadataTraining;
SET NOCOUNT ON;
SET ARITHABORT ON;
DROP INDEX nix_temp_01 ON Enrollment.Enrollment;
DELETE Marketing.Delivery
WHERE SendDate >= '20240101' AND SendDate < '20250101';
CREATE TABLE #Sink (LastName varchar(50), FirstName varchar(50), Company varchar(100),
                    WaitingList bit);
DECLARE @i int = 0, @s int;
WHILE @i < 300
BEGIN
    SET @s = 9000 + @i * 7;
    INSERT #Sink EXEC Enrollment.GetAttendanceSheet @SessionId = @s;
    TRUNCATE TABLE #Sink;
    SET @i += 1;
END;
GO
SELECT 'The night is over: run your routine.' AS Result;
