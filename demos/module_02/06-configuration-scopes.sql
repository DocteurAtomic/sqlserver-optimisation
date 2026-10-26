-- Clip 2.4: the three scopes of a setting, shown on MAXDOP. Runs on the lab, in one
-- session. The instance is only read; the database setting is changed, then put back to 2.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- Instance scope: sp_configure, read here in sys.configurations.
SELECT name, value_in_use, is_dynamic, is_advanced
FROM sys.configurations
WHERE name IN (N'max degree of parallelism', N'cost threshold for parallelism');

-- Database scope: ALTER DATABASE SCOPED CONFIGURATION. It travels with the backup.
SELECT name, value, value_for_secondary, is_value_default
FROM sys.database_scoped_configurations
WHERE name = N'MAXDOP';

SELECT COUNT(*) AS DatabaseScopedConfigurations
FROM sys.database_scoped_configurations;
GO
-- The degree of parallelism actually used is read in the plan cache, after each query
-- (last_dop). The marker in the comment finds the query; the lookup builds it in two
-- pieces so as not to find itself.
SELECT COUNT(*) AS Events FROM Elearning.Activity WHERE EventTime >= '20260101' /* scope-1 */;
GO
SELECT s.last_dop
FROM sys.dm_exec_query_stats AS s
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
WHERE t.text LIKE N'%/* scope' + N'-1 */%';
GO
-- The database setting set to 0: the instance setting applies again.
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 0;
GO
SELECT COUNT(*) AS Events FROM Elearning.Activity WHERE EventTime >= '20260101' /* scope-2 */;
GO
SELECT s.last_dop
FROM sys.dm_exec_query_stats AS s
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
WHERE t.text LIKE N'%/* scope' + N'-2 */%';
GO
-- Back to 2, then the query scope: a hint wins over the database setting, both ways.
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 2;
GO
SELECT COUNT(*) AS Events FROM Elearning.Activity WHERE EventTime >= '20260101' /* scope-3 */ OPTION (MAXDOP 4);
GO
SELECT s.last_dop
FROM sys.dm_exec_query_stats AS s
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
WHERE t.text LIKE N'%/* scope' + N'-3 */%';
GO
SELECT COUNT(*) AS Events FROM Elearning.Activity WHERE EventTime >= '20260101' /* scope-4 */ OPTION (MAXDOP 1);
GO
SELECT s.last_dop
FROM sys.dm_exec_query_stats AS s
CROSS APPLY sys.dm_exec_sql_text(s.sql_handle) AS t
WHERE t.text LIKE N'%/* scope' + N'-4 */%';
GO
SELECT name, value FROM sys.database_scoped_configurations WHERE name = N'MAXDOP';
