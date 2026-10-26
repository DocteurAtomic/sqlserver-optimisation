-- Clip D4.1: what tempdb holds. Runs on the lab, in one session, while charge.sh runs (it
-- also runs alone, and then shows a lab at rest).
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The trap: sys.dm_db_file_space_usage describes the files of the current database.
--    Run from a user database, it returns that database, and the three columns that only
--    make sense for tempdb are NULL. A SUM over them returns NULL, without any message.
SELECT DB_NAME(database_id) AS database_name, file_id, total_page_count,
       user_object_reserved_page_count, internal_object_reserved_page_count,
       version_store_reserved_page_count
FROM sys.dm_db_file_space_usage;

-- 2. The same view read in tempdb, here through its three-part name (USE tempdb works too):
--    the reserved space of the three families, in MB, for the eight data files together.
SELECT SUM(user_object_reserved_page_count)     / 128.0 AS user_objects_mb,
       SUM(internal_object_reserved_page_count) / 128.0 AS internal_objects_mb,
       SUM(version_store_reserved_page_count)   / 128.0 AS version_store_mb,
       SUM(unallocated_extent_page_count)       / 128.0 AS free_mb,
       SUM(total_page_count)                    / 128.0 AS total_mb,
       COUNT(*)                                         AS data_files
FROM tempdb.sys.dm_db_file_space_usage;

-- 3. The files of tempdb: size, growth, maximum size.
SELECT name, type_desc, size / 128 AS size_mb, growth / 128 AS growth_mb,
       IIF(max_size = -1, N'unlimited', CONVERT(nvarchar(20), max_size / 128)) AS max_size_mb
FROM tempdb.sys.database_files
ORDER BY file_id;
