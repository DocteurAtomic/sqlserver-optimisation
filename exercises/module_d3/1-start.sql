-- Module D3 exercise: start. Runs on your lab, in one session.
-- Restores PachadataTraining as delivered (PARAMETERIZATION SIMPLE), creates the exercise
-- database ExoWaits (dropped at the end of 3-solution.sql), then gives the skeleton of the
-- three parts, to complete where it says "Your turn". Nothing here changes the instance:
-- the options of part 3 are set on ExoWaits alone.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
DROP DATABASE IF EXISTS ExoWaits;
GO
CREATE DATABASE ExoWaits;
GO
ALTER DATABASE ExoWaits SET RECOVERY SIMPLE;
GO
USE ExoWaits;
GO
-- Part 1: the table that 2-load.sql fills one row at a time.
CREATE TABLE dbo.ClickLog (
    ClickId int IDENTITY CONSTRAINT pk_ClickLog PRIMARY KEY,
    ClickTime datetime2(3) NOT NULL CONSTRAINT df_ClickLog_ClickTime DEFAULT SYSDATETIME(),
    Page varchar(100) NOT NULL
);
-- Part 3: 300,000 prospects copied from PachadataTraining.
SELECT TOP (300000) IDENTITY(int, 1, 1) AS ProspectId, p.FirstName, p.LastName, p.City, p.ZipCode
INTO dbo.Prospect
FROM PachadataTraining.Contact.ProspectUS AS p;
ALTER TABLE dbo.Prospect ADD CONSTRAINT pk_Prospect PRIMARY KEY CLUSTERED (ProspectId);
GO
SELECT (SELECT COUNT(*) FROM dbo.ClickLog) AS clicks, (SELECT COUNT(*) FROM dbo.Prospect) AS prospects;
GO

-- The skeleton does not run until you remove the line SET NOEXEC ON.
SET NOEXEC ON;
GO
-- Part 1. In window 1, run 2-load.sql (45 seconds). In window 2, within five seconds:
-- Your turn: two snapshots of sys.dm_os_wait_stats 30 seconds apart, the difference without
-- the idle waits (the list of demos/module_d3/01a-waits-interval.sql), with the share of
-- each wait, its average and its signal part. Then the waits of the session of 2-load.sql
-- (sys.dm_exec_session_wait_stats), found by its host name or its session_id.

-- Part 2. Two loads of 2,000 batches each, on the page of a session in the catalog.
USE PachadataTraining;
GO
-- Your turn: first reading of Batch Requests/sec and SQL Compilations/sec into a temporary
-- table, with the time, and of the optimizations in sys.dm_exec_query_optimizer_info.
GO
-- Load A: the identifier of the session concatenated into the text.
DECLARE @sql nvarchar(400) = N'SELECT s.SessionId, s.StartDate, cl.Title, r.Name AS Room FROM Course.Session AS s JOIN Course.CourseLanguage AS cl ON cl.CourseId = s.CourseId AND cl.LanguageCode = s.LanguageCode LEFT JOIN Reference.TrainingRoom AS r ON r.TrainingRoomId = s.TrainingRoomId WHERE s.SessionId = '
        + CAST(ABS(CHECKSUM(NEWID())) % 19300 + 1 AS nvarchar(10)) + N';';
EXEC (@sql);
GO 2000
-- Your turn: second reading, per second; reset the first reading for load B.
GO
-- Load B: the same query, with a parameter.
DECLARE @id int = ABS(CHECKSUM(NEWID())) % 19300 + 1;
EXEC sys.sp_executesql
     N'SELECT s.SessionId, s.StartDate, cl.Title, r.Name AS Room FROM Course.Session AS s JOIN Course.CourseLanguage AS cl ON cl.CourseId = s.CourseId AND cl.LanguageCode = s.LanguageCode LEFT JOIN Reference.TrainingRoom AS r ON r.TrainingRoomId = s.TrainingRoomId WHERE s.SessionId = @id;',
     N'@id int', @id = @id;
GO 2000
-- Your turn: second reading of load B, then the plans of each load in the cache, by objtype.

-- Part 3. 500 concatenated queries on ExoWaits.dbo.Prospect, three times.
USE ExoWaits;
GO
-- Your turn: the cache of ExoWaits emptied (ALTER DATABASE SCOPED CONFIGURATION CLEAR
-- PROCEDURE_CACHE), run the loop below, count its plans by cacheobjtype (number, size,
-- used once). Then the same with ALTER DATABASE SCOPED CONFIGURATION SET
-- OPTIMIZE_FOR_AD_HOC_WORKLOADS = ON, then with ALTER DATABASE ExoWaits SET PARAMETERIZATION
-- FORCED, counting the optimizations of each run.
DECLARE @i int = 1, @sql nvarchar(400);
WHILE @i <= 500
BEGIN
    SET @sql = N'SELECT p.LastName, p.City FROM dbo.Prospect AS p JOIN dbo.Prospect AS q ON q.ProspectId = p.ProspectId + 1 WHERE p.ProspectId = '
             + CAST(@i * 500 AS nvarchar(10)) + N';';
    EXEC (@sql);
    SET @i += 1;
END;
GO
SET NOEXEC OFF;
GO
