-- Clip V1.4, the end of the module: the three procedures of the website rewritten, and the
-- same calls measured before and after. Runs on the lab, in one session, after
-- 04a-optional-parameters.sql. Changes the code of the three procedures in this database;
-- 00-setup.sql of the next module restores the database.
USE PachadataTraining;
SET ARITHABORT ON;
GO
SET STATISTICS IO ON;
GO
-- Before: the calls of the website, with the procedures as 00-setup.sql created them.
EXEC sys.sp_recompile N'Course.SearchSessions';
GO
EXEC Course.GetSessionsByYear @Year = 2024;
EXEC Course.SearchSessions @CourseId = 25, @LanguageCode = 'FR';
EXEC Course.SearchSessions @StartDate = '20271201';
EXEC Contact.FindProspectsByName @LastName = N'Kowalski';
GO
SET STATISTICS IO OFF;
GO
-- The fix. 1. The year as a half-open interval on the column.
CREATE OR ALTER PROCEDURE Course.GetSessionsByYear
    @Year int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT SessionId, StartDate, TrainingRoomId
    FROM Course.Session
    WHERE StartDate >= DATEFROMPARTS(@Year, 1, 1)
      AND StartDate <  DATEFROMPARTS(@Year + 1, 1, 1);
END;
GO
-- 2. Only the criteria received, in parameterized dynamic SQL.
CREATE OR ALTER PROCEDURE Course.SearchSessions
    @CourseId     int     = NULL,
    @LanguageCode char(2) = NULL,
    @StartDate    date    = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql nvarchar(max) = N'SELECT SessionId, CourseId, LanguageCode, StartDate, TrainingRoomId, Price
FROM Course.Session
WHERE 1 = 1';
    IF @CourseId     IS NOT NULL SET @sql += N'
  AND CourseId = @CourseId';
    IF @LanguageCode IS NOT NULL SET @sql += N'
  AND LanguageCode = @LanguageCode';
    IF @StartDate    IS NOT NULL SET @sql += N'
  AND StartDate >= @StartDate';
    EXEC sys.sp_executesql @sql,
        N'@CourseId int, @LanguageCode char(2), @StartDate date',
        @CourseId = @CourseId, @LanguageCode = @LanguageCode, @StartDate = @StartDate;
END;
GO
-- 3. The parameter in the type of the column.
CREATE OR ALTER PROCEDURE Contact.FindProspectsByName
    @LastName varchar(50)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT FirstName, LastName, City
    FROM Contact.ProspectUS_SQL_Latin1
    WHERE LastName = @LastName;
END;
GO
SET STATISTICS IO ON;
GO
-- After: the same calls. The application still sends N'Kowalski': the value is converted
-- once, to the type of the parameter, and the column stays as it is.
EXEC Course.GetSessionsByYear @Year = 2024;
EXEC Course.SearchSessions @CourseId = 25, @LanguageCode = 'FR';
EXEC Course.SearchSessions @StartDate = '20271201';
EXEC Contact.FindProspectsByName @LastName = N'Kowalski';
GO
SET STATISTICS IO OFF;
GO
