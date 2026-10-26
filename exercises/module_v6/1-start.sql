-- Exercise of module V6, start. Runs on the lab, in one session. It lasts a few seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. Creates two pieces of code written as they are often found in production:
--    a. Enrollment.CashRunningTotal, the cash collected per day of a year and the running
--       total since January 1: a WHILE loop fills a table variable with the days of the
--       year, then a cursor walks the days, sums the payments of each one and accumulates.
--    b. Course.GetFillStatus, a scalar function that gives the fill status of a session
--       (NO ROOM, FULL, ALMOST FULL, OPEN) from the seats of its room and the enrollments,
--       written with one RETURN per case; and Course.SessionList, the list of the sessions of
--       a period that calls it once per session.
-- 3. Gives the calls of the two parts.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
CREATE OR ALTER PROCEDURE Enrollment.CashRunningTotal
    @Year int
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Days TABLE (PaymentDay date PRIMARY KEY, Amount decimal(19, 2), RunningTotal decimal(19, 2));
    DECLARE @Day date = DATEFROMPARTS(@Year, 1, 1), @Amount decimal(19, 2), @Total decimal(19, 2) = 0;

    -- The calendar of the year, one day per iteration.
    WHILE @Day < DATEFROMPARTS(@Year + 1, 1, 1)
    BEGIN
        INSERT @Days (PaymentDay) VALUES (@Day);
        SET @Day = DATEADD(day, 1, @Day);
    END;

    -- The cash of each day, and the running total.
    DECLARE d CURSOR LOCAL FAST_FORWARD FOR SELECT PaymentDay FROM @Days ORDER BY PaymentDay;
    OPEN d;
    FETCH NEXT FROM d INTO @Day;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @Amount = ISNULL(SUM(Amount), 0) FROM Enrollment.Payment WHERE PaymentDate = @Day;
        SET @Total += @Amount;
        UPDATE @Days SET Amount = @Amount, RunningTotal = @Total WHERE PaymentDay = @Day;
        FETCH NEXT FROM d INTO @Day;
    END;
    CLOSE d;
    DEALLOCATE d;

    SELECT PaymentDay, Amount, RunningTotal FROM @Days ORDER BY PaymentDay;
END;
GO
CREATE OR ALTER FUNCTION Course.GetFillStatus (@SessionId int)
RETURNS varchar(12)
AS
BEGIN
    DECLARE @Seats int, @Enrolled int;
    SELECT @Seats = r.Seats
    FROM Course.Session AS s
    JOIN Reference.TrainingRoom AS r ON r.TrainingRoomId = s.TrainingRoomId
    WHERE s.SessionId = @SessionId;
    IF @Seats IS NULL RETURN 'NO ROOM';
    SELECT @Enrolled = COUNT(*)
    FROM Enrollment.Enrollment
    WHERE SessionId = @SessionId AND WaitingList = 0 AND CancellationDate IS NULL;
    IF @Enrolled >= @Seats RETURN 'FULL';
    IF @Enrolled >= @Seats * 0.8 RETURN 'ALMOST FULL';
    RETURN 'OPEN';
END;
GO
CREATE OR ALTER PROCEDURE Course.SessionList
    @Start date,
    @End   date
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.SessionId, s.CourseId, s.StartDate, s.StatusCode,
           Course.GetFillStatus(s.SessionId) AS FillStatus
    FROM Course.Session AS s
    WHERE s.StartDate >= @Start AND s.StartDate <= @End
    ORDER BY s.StartDate, s.SessionId;
END;
GO
-- Part 1. The cash of 2025. SET STATISTICS IO and TIME stay off around the procedure: they
-- write one message per statement of the loop. Read the reads and the CPU time in
-- sys.dm_exec_procedure_stats after the call.
/*
EXEC Enrollment.CashRunningTotal @Year = 2025;
*/
-- Part 2. The sessions of 2024 to 2026, with their fill status.
/*
EXEC Course.SessionList @Start = '20240101', @End = '20261231';
*/
