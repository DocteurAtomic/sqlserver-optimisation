-- Clip V1.1: sargability. A function, a calculation or a leading wildcard on the filtered
-- column, and what the index can still seek. Runs on the lab, in one session, after
-- 00-setup.sql. Reads only. Turn on the actual plan in SSMS (Ctrl+M); the pages read are in
-- the Messages tab.
USE PachadataTraining;
GO
-- The index the yearly catalogue could use: uq_Session_StartDateRoom, key StartDate then
-- TrainingRoomId. SessionId, the key of the clustered index, is in every nonclustered index.
SELECT i.name AS IndexName, i.type_desc AS IndexType, c.name AS KeyColumn, ic.key_ordinal
FROM sys.indexes AS i
JOIN sys.index_columns AS ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns AS c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID(N'Course.Session')
ORDER BY i.index_id, ic.key_ordinal;
GO
SET STATISTICS IO ON;
GO
-- 1. The page of the yearly catalogue, as the website calls it.
EXEC Course.GetSessionsByYear @Year = 2024;
GO
-- 2. The same query, the column left alone: a half-open interval on StartDate.
DECLARE @Year int = 2024;
SELECT SessionId, StartDate, TrainingRoomId
FROM Course.Session
WHERE StartDate >= DATEFROMPARTS(@Year, 1, 1)
  AND StartDate <  DATEFROMPARTS(@Year + 1, 1, 1);
GO
-- 3. The coming 30 days: the calculation on the column, then on the constant.
SELECT SessionId, StartDate, TrainingRoomId
FROM Course.Session
WHERE DATEDIFF(day, '20261018', StartDate) BETWEEN 0 AND 30;

SELECT SessionId, StartDate, TrainingRoomId
FROM Course.Session
WHERE StartDate >= '20261018' AND StartDate < DATEADD(day, 31, '20261018');
GO
-- 4. Strings, on the index nix_contact_lastname of Contact.Contact (238 pages).
--    A function on the column, then the prefix written with LIKE, then a leading wildcard.
SELECT ContactId, LastName
FROM Contact.Contact
WHERE LEFT(LastName, 3) = 'Wag';

SELECT ContactId, LastName
FROM Contact.Contact
WHERE LastName LIKE 'Wag%';

SELECT ContactId, LastName
FROM Contact.Contact
WHERE LastName LIKE '%ner';
GO
-- 5. UPPER on the column, useless under a case-insensitive collation (French_CI_AS),
--    then the plain comparison.
SELECT ContactId, LastName
FROM Contact.Contact
WHERE UPPER(LastName) = 'WAGNER';

SELECT ContactId, LastName
FROM Contact.Contact
WHERE LastName = 'Wagner';
GO
SET STATISTICS IO OFF;
GO
