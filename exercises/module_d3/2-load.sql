-- Module D3 exercise: the load of part 1. Runs on your lab, in window 1, after 1-start.sql;
-- the reading of part 1 runs in window 2 while this one runs. Lasts 45 seconds.
-- It alternates 500 inserts, each one in its own transaction, into ExoWaits.dbo.ClickLog, and
-- a count of the prospects of one city over Contact.ProspectUS (a heap of one million rows,
-- read whole by a parallel plan).
USE ExoWaits;
SET NOCOUNT ON;
DECLARE @end datetime2 = DATEADD(SECOND, 45, SYSDATETIME()), @i int, @n int;
WHILE SYSDATETIME() < @end
BEGIN
    SET @i = 0;
    WHILE @i < 500
    BEGIN
        INSERT INTO dbo.ClickLog (Page) VALUES ('/catalog/sql-server');
        SET @i += 1;
    END;
    SELECT @n = COUNT(*)
    FROM PachadataTraining.Contact.ProspectUS
    WHERE City = 'Boston';
END;
SELECT COUNT(*) AS clicks_inserted FROM dbo.ClickLog;
