-- Module V8, setup. Runs on the lab, in one session, before the first clip of the module.
-- It lasts a few seconds.
-- This module has no problem of its own: it replays, at compatibility level 170 and with
-- every intelligent query processing feature at its default, three problems of the
-- previous modules, and measures what the engine corrects by itself.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170. The restore
--    brings back the defaults that V1 (OPTIONAL_PARAMETER_OPTIMIZATION) and V3
--    (CE_FEEDBACK_FOR_EXPRESSIONS) had turned off.
-- 2. Creates again two procedures of the previous modules, as they were written there:
--    - Course.SearchSessions, the search with optional criteria of module V1
--      (Col = @p OR @p IS NULL), and the first search of the day, by course and language;
--    - Marketing.GetCampaignTargets, the targeting report of module V3. Clip V8.3 replays
--      the rest of the V3 problem (the statistics of Contact.Contact dropped).
-- 3. Creates Contact.ListProspectsByZip, a sort whose size depends on its parameter, for
--    clip V8.2.
-- The table variable of module V6 needs no setup: clip V8.1 declares it.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
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
CREATE OR ALTER PROCEDURE Marketing.GetCampaignTargets
    @Gender     char(1),
    @BornFrom   date,
    @BornBefore date
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.ContactId, c.LastName, c.FirstName,
           COUNT(*)                    AS Deliveries,
           SUM(CAST(d.Opened AS int))  AS Opened,
           SUM(CAST(d.Clicked AS int)) AS Clicked
    FROM Contact.Contact AS c
    JOIN Marketing.Delivery AS d ON d.ContactId = c.ContactId
    WHERE c.Gender = @Gender
      AND c.BirthDate >= @BornFrom
      AND c.BirthDate <  @BornBefore
    GROUP BY c.ContactId, c.LastName, c.FirstName;
END;
GO
-- The prospects of a zip code, or of a range of zip codes ('9%'), sorted by name. The rows
-- go to variables: what is measured is the memory of the sort, not the display.
CREATE OR ALTER PROCEDURE Contact.ListProspectsByZip
    @Zip varchar(10)
AS
BEGIN
    DECLARE @FirstName varchar(50), @LastName varchar(50), @Email varchar(100);
    SELECT @FirstName = FirstName, @LastName = LastName, @Email = Email
    FROM Contact.ProspectUS
    WHERE ZipCode LIKE @Zip
    ORDER BY LastName, FirstName, Email;
END;
GO
-- The first search of the day on the website: course 25, in French, as in module V1.
-- SET ARITHABORT ON makes this session match SSMS.
SET ARITHABORT ON;
EXEC Course.SearchSessions @CourseId = 25, @LanguageCode = 'FR';
GO
SELECT name, value
FROM sys.database_scoped_configurations
WHERE name IN (N'MAXDOP', N'DEFERRED_COMPILATION_TV', N'ROW_MODE_MEMORY_GRANT_FEEDBACK',
               N'MEMORY_GRANT_FEEDBACK_PERCENTILE_GRANT', N'MEMORY_GRANT_FEEDBACK_PERSISTENCE',
               N'DOP_FEEDBACK', N'CE_FEEDBACK', N'CE_FEEDBACK_FOR_EXPRESSIONS',
               N'OPTIONAL_PARAMETER_OPTIMIZATION')
ORDER BY name;
