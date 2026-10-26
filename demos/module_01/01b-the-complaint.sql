-- Clip 1.1: the complaint, measured from the website's seat. Runs on the lab, in one session,
-- while charge.sh runs. Reads only.
USE PachadataTraining;
GO
SET STATISTICS IO, TIME ON;
GO
-- The list of the enrollees of session 12000, as the website sends it.
EXEC sys.sp_executesql N'SELECT e.EnrollmentId, c.LastName, c.FirstName, c.Email,
       e.CreationDate, e.WaitingList
FROM Enrollment.Enrollment AS e
JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
WHERE e.SessionId = @SessionId
  AND e.CancellationDate IS NULL
ORDER BY c.LastName, c.FirstName;', N'@SessionId int', @SessionId = 12000;
GO
SET STATISTICS IO, TIME OFF;
GO
