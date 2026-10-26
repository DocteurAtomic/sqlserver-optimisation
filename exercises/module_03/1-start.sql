/*
Module 3 exercise: read three execution plans, on other tables than the demonstrations.
Restores PachadataTraining as delivered. Runs on the lab, in one session.
The questions are in README.md; the solution is 2-solution.sql.
In SSMS, turn on the actual plan (Ctrl+M) before running each query of the exercise.
*/
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
-- The indexes of the tables of the exercise.
SELECT OBJECT_SCHEMA_NAME(i.object_id) + N'.' + OBJECT_NAME(i.object_id) AS TableName,
       i.name AS IndexName, i.type_desc AS IndexType,
       STRING_AGG(c.name, N', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS KeyColumns
FROM sys.indexes AS i
JOIN sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
                            AND ic.is_included_column = 0
JOIN sys.columns AS c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.object_id IN (OBJECT_ID(N'Course.Session'), OBJECT_ID(N'Enrollment.Evaluation'),
                      OBJECT_ID(N'Enrollment.Answer'), OBJECT_ID(N'Enrollment.Question'),
                      OBJECT_ID(N'Elearning.Activity'))
GROUP BY i.object_id, i.index_id, i.name, i.type_desc
ORDER BY TableName, i.index_id;
GO
