-- Exercise of module V8, start. Runs on the lab, in one session. It lasts a few seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. Creates two procedures written as they are often found in production:
--    a. Elearning.LongestActivities, the e-learning events of the first two million, from a
--       date and above a duration, sorted by duration. Its developer copied the parameters
--       into local variables "to avoid parameter sniffing": the optimizer guesses the
--       selectivity of both filters, and the sort receives too little memory.
--    b. Contact.FindProspects, the search of the sales team in the US prospects, by zip
--       code or by last name, both optional (Col = @p OR @p IS NULL). The delivered database has an
--       index on ZipCode (nix_prospectus_zipcode); this script adds one on LastName.
-- 3. Gives the calls of the two parts.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
CREATE INDEX nix_prospectus_lastname ON Contact.ProspectUS (LastName);
GO
CREATE OR ALTER PROCEDURE Elearning.LongestActivities
    @Since      datetime2,
    @MinSeconds int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @From datetime2 = @Since, @Seconds int = @MinSeconds;
    -- The rows go to variables: what matters here is the memory of the sort.
    DECLARE @ActivityId bigint, @Duration int, @EventTime datetime2, @ContactId int;
    SELECT @ActivityId = ActivityId, @Duration = DurationSeconds,
           @EventTime = EventTime, @ContactId = ContactId
    FROM Elearning.Activity
    WHERE ActivityId <= 2000000 AND EventTime >= @From AND DurationSeconds > @Seconds
    ORDER BY DurationSeconds, EventTime
    OPTION (MAXDOP 1);
END;
GO
CREATE OR ALTER PROCEDURE Contact.FindProspects
    @ZipCode varchar(10) = NULL,
    @LastName varchar(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT FirstName, LastName, ZipCode, City
    FROM Contact.ProspectUS
    WHERE (ZipCode = @ZipCode OR @ZipCode IS NULL)
      AND (LastName = @LastName OR @LastName IS NULL);
END;
GO
-- Part 1:  EXEC Elearning.LongestActivities @Since = '20110101', @MinSeconds = 0;
-- Part 2:  EXEC Contact.FindProspects @LastName = 'Kowalski';
--          EXEC Contact.FindProspects @ZipCode = '62086';
SELECT name, value
FROM sys.database_scoped_configurations
WHERE name IN (N'ROW_MODE_MEMORY_GRANT_FEEDBACK', N'MEMORY_GRANT_FEEDBACK_PERSISTENCE',
               N'MEMORY_GRANT_FEEDBACK_PERCENTILE_GRANT', N'OPTIONAL_PARAMETER_OPTIMIZATION');
