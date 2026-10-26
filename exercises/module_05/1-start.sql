/*
Module 5 exercise: capture with extended events, then read a deadlock.
Restores PachadataTraining as delivered and creates dbo.ExerciseWorkload, the load that
part 1 observes. Runs on the lab, in one session. The questions are in README.md.
Part 1: 2-solution-capture.sql. Part 2: 3a-window-1.sql and 3b-window-2.sql, in two
windows, then 4-solution-deadlock.sql.
*/
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
-- The load of part 1: what an application would send in a few seconds.
CREATE OR ALTER PROCEDURE dbo.ExerciseWorkload
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @i int = 1, @sql nvarchar(400), @n int;

    -- 1. 300 lookups of a contact by its identifier, the text built by concatenation.
    WHILE @i <= 300
    BEGIN
        SET @sql = N'DECLARE @name varchar(50); SELECT @name = LastName FROM Contact.Contact WHERE ContactId = '
                 + CAST(@i * 97 AS nvarchar(10)) + N';';
        EXEC (@sql);
        SET @i += 1;
    END;

    -- 2. 100 searches by name, with a parameter.
    SET @i = 1;
    WHILE @i <= 100
    BEGIN
        EXEC sys.sp_executesql
             N'SELECT @n = COUNT(*) FROM Contact.Contact WHERE LastName = @name',
             N'@name varchar(50), @n int OUTPUT',
             @name = 'Martin', @n = @n OUTPUT;
        SET @i += 1;
    END;

    -- 3. Three reports that read whole tables.
    SELECT a.EventTypeCode, COUNT(*) AS Events
    FROM Elearning.Activity AS a
    WHERE a.ContactId = 53616
    GROUP BY a.EventTypeCode;

    SELECT a.Device, COUNT(*) AS Events, SUM(a.DurationSeconds) AS Seconds
    FROM Elearning.Activity AS a
    GROUP BY a.Device;

    SELECT TOP (5) d.CampaignId, COUNT(*) AS Opened
    FROM Marketing.Delivery AS d
    WHERE d.Opened = 1
    GROUP BY d.CampaignId
    ORDER BY Opened DESC;
END;
GO
-- The invoice and the payment of part 2.
SELECT p.PaymentId, p.InvoiceCode, p.SlipNumber, i.ReminderLevel, i.ReminderDate
FROM Enrollment.Payment AS p
JOIN Enrollment.Invoice AS i ON i.InvoiceCode = p.InvoiceCode
WHERE p.PaymentId = 106875;
GO
