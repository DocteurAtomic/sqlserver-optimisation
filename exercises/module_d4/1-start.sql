-- Module D4 exercise: start. Runs on your lab, in one session (window 1).
-- Creates the exercise database ExoTempdb (dropped at the end of 3-solution.sql), with
-- READ_COMMITTED_SNAPSHOT on like PachadataTraining, copies the prospects of
-- PachadataTraining into dbo.Prospect, creates the procedure of part 2, then gives the
-- skeleton of the two parts, to complete where it says "Your turn". Nothing here changes
-- the instance. Play it after the 99-cleanup.sql of the module, charge.sh stopped.
USE master;
GO
IF DB_ID(N'ExoTempdb') IS NOT NULL
BEGIN
    ALTER DATABASE ExoTempdb SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ExoTempdb;
END;
GO
CREATE DATABASE ExoTempdb;
GO
ALTER DATABASE ExoTempdb SET RECOVERY SIMPLE;
ALTER DATABASE ExoTempdb SET READ_COMMITTED_SNAPSHOT ON;
GO
USE ExoTempdb;
GO
SELECT IDENTITY(int, 1, 1) AS ProspectId, p.FirstName, p.LastName, p.Address, p.ZipCode,
       p.City, p.Phone, p.Email
INTO dbo.Prospect
FROM PachadataTraining.Contact.ProspectUS AS p;
ALTER TABLE dbo.Prospect ADD CONSTRAINT pk_Prospect PRIMARY KEY CLUSTERED (ProspectId);
CREATE INDEX nix_Prospect_ZipCode ON dbo.Prospect (ZipCode);
GO
-- Part 2: the mailing tool calls this procedure for each ZIP code. It keeps the first
-- fifty prospects of the code in a temporary table, then returns them.
CREATE OR ALTER PROCEDURE dbo.GetMailingBatch
    @ZipCode varchar(10)
AS
SET NOCOUNT ON;
CREATE TABLE #Batch (
    ProspectId int NOT NULL CONSTRAINT pk_Batch PRIMARY KEY,
    LastName varchar(50) NULL,
    City varchar(50) NULL
);
INSERT INTO #Batch (ProspectId, LastName, City)
SELECT TOP (50) ProspectId, LastName, City
FROM dbo.Prospect
WHERE ZipCode = @ZipCode
ORDER BY ProspectId;
SELECT ProspectId, LastName, City FROM #Batch;
GO
SELECT COUNT(*) AS prospects, COUNT(DISTINCT ZipCode) AS zip_codes FROM dbo.Prospect;
GO

-- The skeleton. Remove the next line to run it, part by part.
SET NOEXEC ON;
GO
-------------------------------------------------------------------------------------------
-- Part 1. What fills tempdb. Window 1, in one session: the temporary table and the
-- counters of the session belong to it.
-------------------------------------------------------------------------------------------
USE ExoTempdb;
SET NOCOUNT ON;
GO
-- 1. A temporary table of all the prospects.
SELECT ProspectId, FirstName, LastName, Address, ZipCode, City, Phone, Email
INTO #Prospect
FROM dbo.Prospect;
GO
-- Your turn: the pages this session allocated and deallocated (sys.dm_db_session_space_usage),
-- and what tempdb holds, by family (sys.dm_db_file_space_usage, read in tempdb).
GO
-- 2. A sort that the memory grant cannot hold: it spills into tempdb.
DECLARE @Email varchar(100);
SELECT @Email = Email
FROM dbo.Prospect
ORDER BY Email, LastName
OPTION (MAX_GRANT_PERCENT = 0.1);
GO
-- Your turn: the same session counters, read again. What changed, and what is left?
GO
-- 3. Start 2-forgotten-transaction.sql in a second window, then, here, update all the
--    other prospects (the update is committed at once).
UPDATE dbo.Prospect SET Phone = CONCAT('1-', Phone) WHERE ProspectId > 1;
GO
-- Your turn: the version store per database (sys.dm_tran_version_store_space_usage) and the
-- transactions that may still need a version (sys.dm_tran_active_snapshot_database_transactions),
-- now, a minute and a half later, then once the second window has ended.
GO
-------------------------------------------------------------------------------------------
-- Part 2. A procedure that creates its temporary table at each call.
-------------------------------------------------------------------------------------------
-- 2,000 calls of the mailing procedure, ZIP codes taken in turn.
DECLARE @zip TABLE (n int IDENTITY PRIMARY KEY, ZipCode varchar(10));
INSERT INTO @zip (ZipCode) SELECT DISTINCT ZipCode FROM dbo.Prospect WHERE ZipCode IS NOT NULL;
DECLARE @i int = 0, @n int = (SELECT COUNT(*) FROM @zip), @z varchar(10);
WHILE @i < 2000
BEGIN
    SELECT @z = ZipCode FROM @zip WHERE n = 1 + @i % @n;
    EXEC dbo.GetMailingBatch @ZipCode = @z;
    SET @i += 1;
END;
GO
-- Your turn: read Temp Tables Creation Rate before and after the 2,000 calls. How many
-- temporary tables did the instance really create? Change the procedure so that SQL Server
-- can cache its table, and measure again.
GO
SET NOEXEC OFF;
GO
