-- Module 4, setup. Runs on the lab, in one session, before the first clip of the module.
-- It lasts about a minute: it waits for the next Query Store interval between the two
-- periods of the load.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. Query Store: emptied (the queries of the restore), interval of one minute and capture of
--    every query, as in the delivered backup (in production: 60 minutes and AUTO).
-- 3. The problem of the module. A healthy period of the back-office search by last name,
--    Contact.GetContactByName, is played first: its plan, compiled for a rare name, seeks the
--    index nix_contact_lastname (about 10 pages a call). Then sp_recompile throws the plan
--    away, and the first call after it asks for N'Simon', the most frequent name (782
--    contacts): the plan compiled for it scans the clustered index (2,738 pages), and every
--    call that follows reuses it. Query Store keeps both plans. The parameter sensitive plan
--    optimization (PSP) stays on: measured, it does not handle this query.
-- 4. The statements of this script itself (the loops, the INSERT ... EXEC) are removed from
--    Query Store at the end: only the query of the procedure remains.
-- SET ARITHABORT ON makes this session match SSMS: a different value would compile and store
-- a separate plan, and SSMS would not see the regression.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
SET NOCOUNT ON;
SET ARITHABORT ON;
ALTER DATABASE CURRENT SET QUERY_STORE (OPERATION_MODE = READ_WRITE,
    INTERVAL_LENGTH_MINUTES = 1, QUERY_CAPTURE_MODE = ALL);
ALTER DATABASE CURRENT SET QUERY_STORE CLEAR;
GO
-- The names the back office looks for: 400 rare names (one to three contacts each),
-- and every 50th call one of the two most frequent names.
USE PachadataTraining;
SET NOCOUNT ON;
SET ARITHABORT ON;
CREATE TABLE #Names (n int IDENTITY PRIMARY KEY, LastName nvarchar(50));
INSERT #Names (LastName)
SELECT TOP (400) LastName
FROM Contact.Contact
GROUP BY LastName
HAVING COUNT(*) <= 3
ORDER BY LastName;
UPDATE #Names SET LastName = CASE WHEN n % 100 = 0 THEN N'Simon' ELSE N'Martin' END
WHERE n % 50 = 0;
-- The results are kept in a temporary table rather than sent to the screen: 800 result sets
-- would flood SSMS. Query Store counts about 6 more pages per call for this INSERT.
CREATE TABLE #Sink (LastName varchar(50), FirstName varchar(50), Email varchar(150),
                    Phone varchar(15), Fax varchar(15));

-- Healthy period: the first call compiles the plan for a rare name.
DECLARE @i int = 1, @name nvarchar(50);
WHILE @i <= 400
BEGIN
    SELECT @name = LastName FROM #Names WHERE n = @i;
    INSERT #Sink EXEC Contact.GetContactByName @LastName = @name;
    SET @i += 1;
END;

-- Wait for the next one-minute interval, so that the two periods are stored apart.
DECLARE @now datetime2 = SYSUTCDATETIME();
DECLARE @wait char(12) = CONVERT(char(12),
    DATEADD(millisecond, 61000 - DATEPART(second, @now) * 1000 - DATEPART(millisecond, @now),
            CAST('00:00:00' AS time)), 114);
WAITFOR DELAY @wait;

-- The sabotage: the plan is thrown away, and the first call that follows asks for Simon.
EXEC sys.sp_recompile N'Contact.GetContactByName';
INSERT #Sink EXEC Contact.GetContactByName @LastName = N'Simon';

-- Regressed period: the same calls, with the plan compiled for Simon.
SET @i = 1;
WHILE @i <= 400
BEGIN
    SELECT @name = LastName FROM #Names WHERE n = @i;
    INSERT #Sink EXEC Contact.GetContactByName @LastName = @name;
    SET @i += 1;
END;
DROP TABLE #Sink, #Names;
GO
-- The statements of this script are removed from Query Store, so that only the query of the
-- procedure remains, as the application would have left it.
USE PachadataTraining;
DECLARE @q bigint;
DECLARE load_queries CURSOR LOCAL FAST_FORWARD FOR
    SELECT q.query_id
    FROM sys.query_store_query AS q
    JOIN sys.query_store_query_text AS qt ON qt.query_text_id = q.query_text_id
    WHERE q.object_id = 0;
OPEN load_queries;
FETCH NEXT FROM load_queries INTO @q;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sys.sp_query_store_remove_query @query_id = @q;
    FETCH NEXT FROM load_queries INTO @q;
END;
CLOSE load_queries;
DEALLOCATE load_queries;
GO
SELECT name, value
FROM sys.database_scoped_configurations
WHERE name = N'PARAMETER_SENSITIVE_PLAN_OPTIMIZATION';
