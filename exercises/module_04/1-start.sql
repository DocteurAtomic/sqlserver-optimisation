/*
Module 4 exercise: a regression found and corrected with Query Store, on another procedure
than the demonstrations. Runs on the lab, in one session; it lasts about a minute.
Restores PachadataTraining as delivered, empties its Query Store, then plays a load on
Contact.ProspectsByParameter (prospects by zip code, LIKE @zip): a first period, a
recompilation, and the period that follows. Something went wrong in between: find it.
The questions are in README.md; the solution is 2-solution.sql.
SET ARITHABORT ON makes this session match SSMS.
*/
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
USE PachadataTraining;
SET NOCOUNT ON;
SET ARITHABORT ON;
-- 300 zip codes, as the marketing team looks them up.
CREATE TABLE #Zips (n int IDENTITY PRIMARY KEY, ZipCode varchar(10));
INSERT #Zips (ZipCode)
SELECT TOP (300) ZipCode
FROM Contact.ProspectUS
WHERE ZipCode >= '10000'
GROUP BY ZipCode
ORDER BY ZipCode;
CREATE TABLE #Sink (LastName varchar(50), FirstName varchar(50));

DECLARE @i int = 1, @zip varchar(10);
WHILE @i <= 300
BEGIN
    SELECT @zip = ZipCode FROM #Zips WHERE n = @i;
    INSERT #Sink EXEC Contact.ProspectsByParameter @zip = @zip;
    SET @i += 1;
END;

DECLARE @now datetime2 = SYSUTCDATETIME();
DECLARE @wait char(12) = CONVERT(char(12),
    DATEADD(millisecond, 61000 - DATEPART(second, @now) * 1000 - DATEPART(millisecond, @now),
            CAST('00:00:00' AS time)), 114);
WAITFOR DELAY @wait;

EXEC sys.sp_recompile N'Contact.ProspectsByParameter';
INSERT #Sink EXEC Contact.ProspectsByParameter @zip = '9%';

SET @i = 1;
WHILE @i <= 300
BEGIN
    SELECT @zip = ZipCode FROM #Zips WHERE n = @i;
    INSERT #Sink EXEC Contact.ProspectsByParameter @zip = @zip;
    SET @i += 1;
END;
DROP TABLE #Sink, #Zips;
GO
-- The statements of this script are removed from Query Store: only the procedure remains.
USE PachadataTraining;
DECLARE @q bigint;
DECLARE load_queries CURSOR LOCAL FAST_FORWARD FOR
    SELECT query_id FROM sys.query_store_query WHERE object_id = 0;
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
PRINT N'Load done: the zip code search of the marketing team has become slow.';
