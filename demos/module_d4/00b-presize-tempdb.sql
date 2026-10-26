-- Module D4, setup, second part: tempdb preallocated before the load. Runs in one session,
-- on the lab, after 00-setup.sql and before charge.sh.
-- ci: skip (it changes the size of the files of tempdb, an instance setting)
-- The lab starts with eight data files of 8 MB, growing by 64 MB. Under the load of the
-- module, the files grow in the first seconds, and again later. On SQL Server 2025 CU7,
-- each growth left one call of the procedure stuck in the statement it was running (an
-- INSERT or a CREATE INDEX; measured on 26 October 2026, at every growth of five tries, and
-- reproduced on 2025 CU10 and 2022 CU27): stuck for as long as the load lasts, spending its
-- time destroying the temporary tables the other sessions dropped (event
-- temp_table_destroy_list_trace), its logical reads growing by about 45,000 a second, and its
-- open transaction keeping the log of tempdb from being truncated (it grew from 8 MB to
-- 1.5 GB in two minutes). Details and a standalone repro: research folder of the course. With the files preallocated, no try showed it. The module measures
-- the contention, not this incident: the files are preallocated to 256 MB each, a size the
-- load of the module does not fill. ALTER DATABASE ... MODIFY FILE grows the files at once
-- and records the size for the next starts; 99-cleanup.sql puts back 8 MB.
USE master;
SET NOCOUNT ON;
GO
DECLARE @sql nvarchar(max) = N'';
SELECT @sql += N'ALTER DATABASE tempdb MODIFY FILE (NAME = ' + QUOTENAME(name)
             + N', SIZE = 256MB); '
FROM tempdb.sys.database_files
WHERE type_desc = N'ROWS' AND size < 256 * 128;
EXEC (@sql);
GO
SELECT name, size / 128 AS size_mb, growth / 128 AS growth_mb
FROM tempdb.sys.database_files
ORDER BY file_id;
