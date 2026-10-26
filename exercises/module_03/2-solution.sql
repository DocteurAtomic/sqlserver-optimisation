-- Module 3 exercise: solution. Runs on the lab, in one session, after 1-start.sql. Turn on
-- the actual plan in SSMS (Ctrl+M): the answers are read in the plans, the pages in the
-- Messages tab. It leaves nothing behind: the index of part 3 is dropped at the end.
USE PachadataTraining;
GO
SET STATISTICS IO ON;
GO
-- Part 1. The sessions of a course.
-- 1.1 Course 169, the course with the most sessions: a Clustered Index Scan of pk_Session,
--     although nix_temp_02 starts with CourseId.
SELECT s.SessionId, s.StartDate, s.Price, s.StatusCode
FROM Course.Session AS s
WHERE s.CourseId = 169;
GO
-- 1.2 Course 106: an Index Seek on nix_temp_02, then a Key Lookup per session.
SELECT s.SessionId, s.StartDate, s.Price, s.StatusCode
FROM Course.Session AS s
WHERE s.CourseId = 106;
GO
-- 1.3 How many sessions per course, and how many pages in the table.
SELECT CourseId, COUNT(*) AS Sessions
FROM Course.Session
WHERE CourseId IN (106, 169)
GROUP BY CourseId;
SELECT used_page_count
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'Course.Session') AND index_id = 1;
GO
-- Part 2. The ratings of the 2026 evaluations, question by question.
SELECT q.Position, q.Label, COUNT(*) AS Answers, AVG(1.0 * a.Rating) AS AverageRating
FROM Enrollment.Evaluation AS v
JOIN Enrollment.Answer AS a ON a.EvaluationId = v.EvaluationId
JOIN Enrollment.Question AS q ON q.QuestionId = a.QuestionId
WHERE v.EvaluationDate >= '20260101'
GROUP BY q.Position, q.Label
ORDER BY q.Position;
GO
-- Part 3. The e-learning events of one learner, by type.
SELECT a.EventTypeCode, COUNT(*) AS Events, SUM(a.DurationSeconds) AS Seconds
FROM Elearning.Activity AS a
WHERE a.ContactId = 53616
GROUP BY a.EventTypeCode;
GO
-- 3.4 The index the plan proposes, created, the query measured again, the index dropped.
CREATE NONCLUSTERED INDEX nix_exercise_03 ON Elearning.Activity (ContactId)
    INCLUDE (EventTypeCode, DurationSeconds);
GO
SELECT a.EventTypeCode, COUNT(*) AS Events, SUM(a.DurationSeconds) AS Seconds
FROM Elearning.Activity AS a
WHERE a.ContactId = 53616
GROUP BY a.EventTypeCode;
GO
SELECT used_page_count AS IndexPages
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'Elearning.Activity')
  AND index_id = INDEXPROPERTY(object_id, N'nix_exercise_03', 'IndexID');
GO
SET STATISTICS IO OFF;
GO
DROP INDEX nix_exercise_03 ON Elearning.Activity;
GO
