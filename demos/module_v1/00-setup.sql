-- Module V1, setup. Runs on the lab, in one session, before the first clip of the module.
-- It lasts a few seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. Turns off the optional parameter plan optimization (OPPO) of SQL Server 2025 for the
--    database (OPTIONAL_PARAMETER_OPTIMIZATION = OFF), so that the optional parameters of
--    clip V1.4 behave as on SQL Server 2022 and earlier. Module V8 turns it back on.
-- 3. Creates the index the sales team searches prospects with, on the copy of the prospects
--    whose columns are in the SQL collation SQL_Latin1_General_CP1_CI_AS.
-- 4. The problem of the module: the three procedures the website calls are created as a
--    hurried developer would write them.
--    - Course.GetSessionsByYear filters on YEAR(StartDate): the index on StartDate is read
--      in full (the code of Demo.SessionsByYear_Slow).
--    - Course.SearchSessions writes its optional criteria (Col = @p OR @p IS NULL): one plan
--      serves every combination of criteria (the code of Demo.SearchSessions_Slow).
--    - Contact.FindProspectsByName declares its parameter nvarchar, compared with a varchar
--      column in a SQL collation: the column is converted and its index scanned.
--    Clip V1.4 rewrites the three and measures.
-- 5. The first search of the day on the website asks for a course in French: the plan of
--    Course.SearchSessions is compiled for it, and stays in the cache.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
ALTER DATABASE SCOPED CONFIGURATION SET OPTIONAL_PARAMETER_OPTIMIZATION = OFF;
GO
CREATE INDEX nix_prospectussql_lastname ON Contact.ProspectUS_SQL_Latin1 (LastName);
GO
CREATE OR ALTER PROCEDURE Course.GetSessionsByYear
    @Year int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT SessionId, StartDate, TrainingRoomId
    FROM Course.Session
    WHERE YEAR(StartDate) = @Year;
END;
GO
CREATE OR ALTER PROCEDURE Course.SearchSessions
    @CourseId     int     = NULL,
    @LanguageCode char(2) = NULL,
    @StartDate    date    = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT SessionId, CourseId, LanguageCode, StartDate, TrainingRoomId, Price
    FROM Course.Session
    WHERE (CourseId = @CourseId OR @CourseId IS NULL)
      AND (LanguageCode = @LanguageCode OR @LanguageCode IS NULL)
      AND (StartDate >= @StartDate OR @StartDate IS NULL);
END;
GO
CREATE OR ALTER PROCEDURE Contact.FindProspectsByName
    @LastName nvarchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT FirstName, LastName, City
    FROM Contact.ProspectUS_SQL_Latin1
    WHERE LastName = @LastName;
END;
GO
-- The first search of the day on the website: course 25, in French. Its plan stays in the
-- cache, and the searches that follow reuse it. SET ARITHABORT ON makes this session match
-- SSMS: a different value would compile a separate plan.
USE PachadataTraining;
SET ARITHABORT ON;
EXEC Course.SearchSessions @CourseId = 25, @LanguageCode = 'FR';
GO
SELECT name, value
FROM sys.database_scoped_configurations
WHERE name = N'OPTIONAL_PARAMETER_OPTIMIZATION';
