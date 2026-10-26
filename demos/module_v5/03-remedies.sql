-- Clip V5.3: the remedies written in the code. Each remedy is a copy of the procedure,
-- called in the order of the morning of the tool: the letter first, then one evaluation.
-- OPTION (RECOMPILE), OPTIMIZE FOR a value, OPTIMIZE FOR UNKNOWN, two branches in the same
-- procedure, and one procedure per kind of campaign. Runs on the lab, in one session, after
-- 02-parameter-sensitivity.sql. The copies are dropped at the end; the site's procedure is
-- not touched.
USE PachadataTraining;
GO
SET NOCOUNT ON;
SET ARITHABORT OFF;
GO
-- 1. OPTION (RECOMPILE): the statement is compiled at each call, for the value of the call.
CREATE OR ALTER PROCEDURE Report.RecipientsByCampaign_Recompile @CampaignId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.LastName, c.FirstName, c.Email, e.SendDate, e.Opened
    FROM Marketing.Delivery AS e
    JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
    WHERE e.CampaignId = @CampaignId
    OPTION (RECOMPILE);
END;
GO
SET STATISTICS IO, TIME ON;
EXEC Report.RecipientsByCampaign_Recompile @CampaignId = 36;
EXEC Report.RecipientsByCampaign_Recompile @CampaignId = 17389;
SET STATISTICS IO, TIME OFF;
GO
-- 2. OPTIMIZE FOR a value: one plan, compiled for a typical evaluation, whatever the call.
CREATE OR ALTER PROCEDURE Report.RecipientsByCampaign_ForEvaluation @CampaignId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.LastName, c.FirstName, c.Email, e.SendDate, e.Opened
    FROM Marketing.Delivery AS e
    JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
    WHERE e.CampaignId = @CampaignId
    OPTION (OPTIMIZE FOR (@CampaignId = 17389));
END;
GO
SET STATISTICS IO, TIME ON;
EXEC Report.RecipientsByCampaign_ForEvaluation @CampaignId = 36;
EXEC Report.RecipientsByCampaign_ForEvaluation @CampaignId = 17389;
SET STATISTICS IO, TIME OFF;
GO
-- 3. OPTIMIZE FOR UNKNOWN: one plan, compiled for the average value of the column
--    (the density of the statistic: 4,018,304 deliveries x 6.0879E-05 = 245 rows).
CREATE OR ALTER PROCEDURE Report.RecipientsByCampaign_Unknown @CampaignId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.LastName, c.FirstName, c.Email, e.SendDate, e.Opened
    FROM Marketing.Delivery AS e
    JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
    WHERE e.CampaignId = @CampaignId
    OPTION (OPTIMIZE FOR UNKNOWN);
END;
GO
SET STATISTICS IO, TIME ON;
EXEC Report.RecipientsByCampaign_Unknown @CampaignId = 36;
EXEC Report.RecipientsByCampaign_Unknown @CampaignId = 17389;
SET STATISTICS IO, TIME OFF;
GO
-- 4. Two branches in the same procedure. Both statements are compiled at the first call,
--    with the value of that call: the branch of the evaluations gets the plan of the letter.
CREATE OR ALTER PROCEDURE Report.RecipientsByCampaign_Branch @CampaignId int
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM Marketing.Campaign
               WHERE CampaignId = @CampaignId AND CampaignType = 'Letter')
        SELECT c.LastName, c.FirstName, c.Email, e.SendDate, e.Opened
        FROM Marketing.Delivery AS e
        JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
        WHERE e.CampaignId = @CampaignId;
    ELSE
        SELECT c.LastName, c.FirstName, c.Email, e.SendDate, e.Opened
        FROM Marketing.Delivery AS e
        JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
        WHERE e.CampaignId = @CampaignId;
END;
GO
SET STATISTICS IO, TIME ON;
EXEC Report.RecipientsByCampaign_Branch @CampaignId = 36;
EXEC Report.RecipientsByCampaign_Branch @CampaignId = 17389;
SET STATISTICS IO, TIME OFF;
GO
-- 5. One procedure per kind of campaign, called by a router: each one is compiled at its
--    own first call, with a value of its own kind.
CREATE OR ALTER PROCEDURE Report.RecipientsOfLetter @CampaignId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.LastName, c.FirstName, c.Email, e.SendDate, e.Opened
    FROM Marketing.Delivery AS e
    JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
    WHERE e.CampaignId = @CampaignId;
END;
GO
CREATE OR ALTER PROCEDURE Report.RecipientsOfEvaluation @CampaignId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.LastName, c.FirstName, c.Email, e.SendDate, e.Opened
    FROM Marketing.Delivery AS e
    JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
    WHERE e.CampaignId = @CampaignId;
END;
GO
CREATE OR ALTER PROCEDURE Report.RecipientsByCampaign_Routed @CampaignId int
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM Marketing.Campaign
               WHERE CampaignId = @CampaignId AND CampaignType = 'Letter')
        EXEC Report.RecipientsOfLetter @CampaignId = @CampaignId;
    ELSE
        EXEC Report.RecipientsOfEvaluation @CampaignId = @CampaignId;
END;
GO
SET STATISTICS IO, TIME ON;
EXEC Report.RecipientsByCampaign_Routed @CampaignId = 36;
EXEC Report.RecipientsByCampaign_Routed @CampaignId = 17389;
SET STATISTICS IO, TIME OFF;
GO
-- 6. The price of OPTION (RECOMPILE): one hundred evaluations, compiled at each call, then
--    served by the procedure of the evaluations, compiled once.
CREATE TABLE #Recipients (LastName varchar(50), FirstName varchar(50), Email varchar(150),
                          SendDate datetime2, Opened bit);
GO
DECLARE @Cpu int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID),
        @CampaignId int = 17291;
WHILE @CampaignId <= 17390
BEGIN
    INSERT INTO #Recipients EXEC Report.RecipientsByCampaign_Recompile @CampaignId = @CampaignId;
    SET @CampaignId += 1;
END;
SELECT 'OPTION (RECOMPILE)' AS Remedy,
       (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID) - @Cpu AS CpuMs;
GO
DECLARE @Cpu int = (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID),
        @CampaignId int = 17291;
WHILE @CampaignId <= 17390
BEGIN
    INSERT INTO #Recipients EXEC Report.RecipientsByCampaign_Routed @CampaignId = @CampaignId;
    SET @CampaignId += 1;
END;
SELECT 'one procedure per kind' AS Remedy,
       (SELECT cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID) - @Cpu AS CpuMs;
GO
DROP TABLE #Recipients;
GO
-- 7. The copies are dropped.
DROP PROCEDURE Report.RecipientsByCampaign_Recompile, Report.RecipientsByCampaign_ForEvaluation,
               Report.RecipientsByCampaign_Unknown, Report.RecipientsByCampaign_Branch,
               Report.RecipientsByCampaign_Routed, Report.RecipientsOfLetter,
               Report.RecipientsOfEvaluation;
GO
