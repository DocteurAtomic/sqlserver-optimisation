-- Module 1 exercise, window 1: the request to observe. Runs on the lab, after the module's
-- 00-setup.sql. Reads only.
-- Note the session number, then run the report: it lasts several seconds, long enough to
-- look at it from window 2 with 2-solution.sql.
USE PachadataTraining;
GO
SELECT @@SPID AS my_session;
GO
EXEC Report.LapsedReaders @Months = 6;
GO
