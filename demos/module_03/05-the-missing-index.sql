-- Clip 3.5: the plan of the enrollees list read operator by operator, the index the
-- 00-setup.sql dropped, recreated, and the measure before and after. Runs on the lab, in
-- one session, after 00-setup.sql. Turn on the actual plan in SSMS (Ctrl+M).
USE PachadataTraining;
GO
-- 1. Before: the list of the enrollees of session 12000, as the website sends it.
SET STATISTICS IO, TIME ON;
GO
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
-- 2. The index the optimizer asked for while compiling, as the instance remembers it
--    until the next restart.
SELECT d.equality_columns, d.inequality_columns, d.included_columns,
       s.user_seeks, CAST(s.avg_user_impact AS decimal(5, 1)) AS avg_user_impact
FROM sys.dm_db_missing_index_details AS d
JOIN sys.dm_db_missing_index_groups AS g ON g.index_handle = d.index_handle
JOIN sys.dm_db_missing_index_group_stats AS s ON s.group_handle = g.index_group_handle
WHERE d.database_id = DB_ID()
  AND d.object_id = OBJECT_ID(N'Enrollment.Enrollment');
GO
-- 3. What 00-setup.sql dropped: nix_temp_01, as the database is delivered. It is recreated
--    as it was, not as the suggestion above describes it.
CREATE NONCLUSTERED INDEX nix_temp_01 ON Enrollment.Enrollment (SessionId)
    INCLUDE (CreationDate);
GO
-- 4. After: the same query, the same session.
SET STATISTICS IO, TIME ON;
GO
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
