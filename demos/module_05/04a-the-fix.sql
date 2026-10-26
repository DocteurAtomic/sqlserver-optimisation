-- Clip 5.4: the fix. Enrollment.SendJoiningInstructions now takes the session first, then
-- the enrollments: the same order as Course.ChangeRoom. Runs on the lab, in one session,
-- after 00-setup.sql. Then run charge.sh again for two minutes, and 04b-after-the-fix.sql.
USE PachadataTraining;
GO
CREATE OR ALTER PROCEDURE Enrollment.SendJoiningInstructions
    @SessionId int
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @TrainingRoomId int;
    BEGIN TRANSACTION;
        -- The session first, as Course.ChangeRoom does: whoever comes second waits for the
        -- first one to commit, instead of holding what the first one needs.
        SELECT @TrainingRoomId = TrainingRoomId
        FROM Course.Session WITH (UPDLOCK)
        WHERE SessionId = @SessionId;

        UPDATE Enrollment.Enrollment
        SET JoiningInstructionsSent = 1
        WHERE SessionId = @SessionId
          AND CancellationDate IS NULL
          AND WaitingList = 0;

        -- The mails are built and queued here, from the enrollments and the room.
    COMMIT;
END;
GO
-- The two procedures now touch the tables in the same order: session, then enrollments.
SELECT OBJECT_SCHEMA_NAME(object_id) + N'.' + name AS procedure_name, modify_date
FROM sys.procedures
WHERE object_id IN (OBJECT_ID(N'Course.ChangeRoom'), OBJECT_ID(N'Enrollment.SendJoiningInstructions'));
GO
