-- Module 5, setup. Runs on the lab, in one session, before the first clip of the module.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. The problem of the module: creates two procedures that write the same two tables in
--    opposite orders.
--    - Course.ChangeRoom, used by the planning team, moves a session to another room:
--      it updates the row of Course.Session, calls the room booking service (a WAITFOR of
--      300 ms stands for that call, made inside the transaction), then resets the flag
--      JoiningInstructionsSent of the enrollments of the session. Session, then enrollments.
--    - Enrollment.SendJoiningInstructions, run by the mailing job, flags the enrollments
--      of a session as sent, then reads the room of the session under an update lock, so
--      that the room cannot change while the mails go out. Enrollments, then session.
--    When the job runs while the planning team moves the same session, each transaction
--    holds what the other one wants: a deadlock, and one of them is rolled back with
--    error 1205. Clip 5.4 changes the order of SendJoiningInstructions.
-- 3. Start the load afterwards: ./demos/module_05/charge.sh
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
CREATE OR ALTER PROCEDURE Course.ChangeRoom
    @SessionId int,
    @TrainingRoomId int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
        UPDATE Course.Session
        SET TrainingRoomId = @TrainingRoomId
        WHERE SessionId = @SessionId;

        -- The room booking service of the training center, called inside the transaction.
        WAITFOR DELAY '00:00:00.300';

        -- The joining instructions give the room: they must be sent again.
        UPDATE Enrollment.Enrollment
        SET JoiningInstructionsSent = 0
        WHERE SessionId = @SessionId
          AND CancellationDate IS NULL
          AND WaitingList = 0;
    COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE Enrollment.SendJoiningInstructions
    @SessionId int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @TrainingRoomId int;
    BEGIN TRANSACTION;
        UPDATE Enrollment.Enrollment
        SET JoiningInstructionsSent = 1
        WHERE SessionId = @SessionId
          AND CancellationDate IS NULL
          AND WaitingList = 0;

        -- The room goes into the mails: it must not change until they are sent.
        SELECT @TrainingRoomId = TrainingRoomId
        FROM Course.Session WITH (UPDLOCK)
        WHERE SessionId = @SessionId;

        -- The mails are built and queued here, from the enrollments and the room.
    COMMIT;
END;
GO
-- The two sessions the load works on: future, inter-company, a dozen enrollees each.
SELECT s.SessionId, s.StartDate, s.TrainingRoomId,
       (SELECT COUNT(*) FROM Enrollment.Enrollment AS e
        WHERE e.SessionId = s.SessionId AND e.CancellationDate IS NULL
          AND e.WaitingList = 0) AS Enrollees
FROM Course.Session AS s
WHERE s.SessionId IN (17651, 17699)
ORDER BY s.SessionId;
