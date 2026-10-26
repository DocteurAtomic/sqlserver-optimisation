-- Clip V3.4: the tipping point between a seek and a scan, measured on the index on LastName.
-- Runs on the lab, in one session, after 03-correcting.sql. Reads only. Turn on the actual
-- plan in SSMS (Ctrl+M); the pages read and the CPU time are in the Messages tab.
-- Contact.Contact: 120,140 rows on 2,740 pages. nix_contact_lastname holds LastName and
-- ContactId only: every other column of SELECT * costs a Key Lookup per row.
USE PachadataTraining;
GO
SET STATISTICS IO, TIME ON;
GO
-- 1. Names starting with Des: 671 contacts, estimated 680.7.
SELECT * FROM Contact.Contact WHERE LastName LIKE 'Des%';
GO
-- 2. The Simons: 782 contacts, estimated 782.
SELECT * FROM Contact.Contact WHERE LastName = 'Simon';
GO
-- 3. The Simons again, the index forced: what the seek would have read.
SELECT * FROM Contact.Contact WITH (INDEX (nix_contact_lastname)) WHERE LastName = 'Simon';
GO
SET STATISTICS IO, TIME OFF;
GO
