-- Exercise of module V1, start. Runs on the lab, in one session. It lasts about twenty
-- seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. Part 2: loads Contact.ContactImport, four copies of Contact.Contact (480,560 rows) typed
--    as a migration tool would type them, without knowing what the columns hold, and in the
--    collation of a default US installation, SQL_Latin1_General_CP1_CI_AS.
-- 3. Gives the queries of part 1 and the skeleton of part 2.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
CREATE TABLE Contact.ContactImport (
    ContactId       bigint        NOT NULL CONSTRAINT pk_ContactImport PRIMARY KEY,
    Title           nvarchar(255) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    LastName        nvarchar(255) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    FirstName       nvarchar(255) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    Email           nvarchar(255) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    Phone           nchar(20)     COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    Gender          nchar(10)     COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    PostalAddressId bigint        NOT NULL,
    CompanyId       bigint        NULL,
    BirthDate       datetime2(7)  NULL
);
-- Four copies of the 120,140 contacts, with shifted identifiers.
INSERT INTO Contact.ContactImport (ContactId, Title, LastName, FirstName, Email, Phone,
                                   Gender, PostalAddressId, CompanyId, BirthDate)
SELECT c.ContactId + 1000000 * (k.n - 1), c.Title, c.LastName, c.FirstName, c.Email,
       c.Phone, c.Gender, c.PostalAddressId, c.CompanyId, c.BirthDate
FROM Contact.Contact AS c
CROSS JOIN (VALUES (1), (2), (3), (4)) AS k (n);

CREATE INDEX nix_contactimport_email ON Contact.ContactImport (Email);
GO
-- Part 1. Three queries on Contact.ProspectUS (1,000,000 rows) and its index on ZipCode,
-- nix_prospectus_zipcode. Run each with SET STATISTICS IO ON and the actual plan, note the
-- pages read and the access operator, then rewrite it so that it seeks in the index.
USE PachadataTraining;
SET STATISTICS IO ON;

-- 1. The prospects whose ZIP code starts with 100 (Manhattan).
SELECT ZipCode, LastName, City
FROM Contact.ProspectUS
WHERE LEFT(ZipCode, 3) = '100';

-- 2. The prospects without a ZIP code, NULL or empty.
SELECT COUNT(*) AS WithoutZipCode
FROM Contact.ProspectUS
WHERE COALESCE(ZipCode, '') = '';

-- 3. The prospects of one ZIP code, as a form sends it.
SELECT ZipCode, LastName, City
FROM Contact.ProspectUS
WHERE ZipCode = 62086;

SET STATISTICS IO OFF;
GO
-- Part 2, the skeleton. Remove the line SET NOEXEC ON once the code is written.
SET NOEXEC ON;
GO
-- Your turn: measure what each column of Contact.ContactImport really holds (maximum
-- length, distinct values, upper bound of the identifiers, time part of the dates).

-- Your turn: create Contact.ContactClean, same columns, the closest types, same collation
-- (SQL_Latin1_General_CP1_CI_AS), and its primary key.

-- Your turn: copy the rows of Contact.ContactImport into it, create the index
-- nix_contactclean_email on Email, and compare the pages of the two tables.

-- Your turn: the application looks a contact up by e-mail, and its driver sends the string
-- in nvarchar(4000). Run the lookup below on both tables and compare.
-- EXEC sys.sp_executesql N'SELECT ContactId, LastName, FirstName FROM Contact.ContactImport WHERE Email = @Email;',
--      N'@Email nvarchar(4000)', @Email = N'a.aba@institut-trefois.fr';
GO
SET NOEXEC OFF;
GO
