-- Clip 3.2: the access operators, scan, seek and lookup, on Contact.Contact and on a heap.
-- Runs on the lab, in one session. Reads only. Turn on the actual plan in SSMS (Ctrl+M)
-- before running each query; the pages read are in the Messages tab.
USE PachadataTraining;
GO
-- The indexes of Contact.Contact: the clustered index on ContactId (the table itself) and a
-- nonclustered index on LastName.
SELECT i.name AS IndexName, i.type_desc AS IndexType, c.name AS KeyColumn
FROM sys.indexes AS i
JOIN sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns AS c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID(N'Contact.Contact')
ORDER BY i.index_id, ic.key_ordinal;
GO
SET STATISTICS IO ON;
GO
-- 1. Clustered Index Seek: one contact by the key of the clustered index.
SELECT ContactId, LastName, FirstName, Email
FROM Contact.Contact
WHERE ContactId = 1234;
GO
-- 2. Clustered Index Scan: no index starts with FirstName, the whole table is read.
SELECT ContactId, LastName, FirstName, Email
FROM Contact.Contact
WHERE FirstName = 'Myriam';
GO
-- 3. Index Seek, then Key Lookup: the index on LastName finds the rows, but holds neither
--    FirstName nor Email; each row found goes back to the clustered index by its key.
SELECT ContactId, LastName, FirstName, Email
FROM Contact.Contact
WHERE LastName = 'Wagner';
GO
-- 4. A more frequent name: the optimizer prefers to read the whole table.
SELECT ContactId, LastName, FirstName, Email
FROM Contact.Contact
WHERE LastName = 'Simon';
GO
-- 5. The cost of a repeated lookup: the index forced by a table hint, on all the names
--    that start with S. Then the same query, left to the optimizer.
SELECT ContactId, LastName, FirstName, Email
FROM Contact.Contact WITH (INDEX (nix_contact_lastname))
WHERE LastName LIKE 'S%';
GO
SELECT ContactId, LastName, FirstName, Email
FROM Contact.Contact
WHERE LastName LIKE 'S%';
GO
-- 6. A heap: Elearning.Activity has no clustered index. Its primary key is a nonclustered
--    index, and the lookup goes to the row by its physical address: RID Lookup.
SELECT ActivityId, EventTime, EventTypeCode, DurationSeconds
FROM Elearning.Activity
WHERE ActivityId = 1000000;
GO
SET STATISTICS IO OFF;
GO
