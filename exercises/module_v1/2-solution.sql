-- Exercise of module V1, solution. Runs on the lab, in one session, after 1-start.sql.
-- Part 1: the three predicates rewritten. Part 2: the profile of the columns, the table with
-- the closest types, the pages compared, then the implicit conversion the new type brought,
-- found in the plan and fixed on the client side. Removes the two tables at the end.
-- The reads quoted were measured on the lab (SORTIES.md of the module); they repeat to a few
-- pages, the times vary from one run to the next.
USE PachadataTraining;
GO
SET STATISTICS IO ON;
GO
-- Part 1.
-- 1. LEFT on the column: nix_prospectus_zipcode is scanned in full (2,843 pages), plus one
--    RID Lookup per row found: 3,767 reads. A prefix is written with LIKE and no leading
--    wildcard, which the optimizer turns into a range: a seek.
SELECT ZipCode, LastName, City
FROM Contact.ProspectUS
WHERE ZipCode LIKE '100%';

-- 2. COALESCE wraps the column in a CASE expression, evaluated for every row: the whole
--    index is read (2,843 pages). The two cases written apart leave the column alone, and
--    become two seek ranges.
SELECT COUNT(*) AS WithoutZipCode
FROM Contact.ProspectUS
WHERE ZipCode IS NULL OR ZipCode = '';

-- 3. The int literal wins over varchar by data type precedence: the column is converted to
--    int, row by row, and the whole table is read (14,752 pages). A literal of the type of
--    the column, or a parameter declared varchar in the application, seeks. The conversion
--    also changed the meaning: a ZIP code stored '06208' would equal 6208.
SELECT ZipCode, LastName, City
FROM Contact.ProspectUS
WHERE ZipCode = '62086';
GO
SET STATISTICS IO OFF;
GO
-- Part 2.
-- 1. What the columns hold. Title 3 characters at most (Mr., Ms.), Gender 1 (M, F), LastName
--    42, FirstName 27, Email 72, Phone 11; identifiers under 3,200,000 for the contacts,
--    133,000 for the addresses, 2,000 for the companies; no birth date has a time part.
SELECT MAX(LEN(Title)) AS Title, MAX(LEN(LastName)) AS LastName,
       MAX(LEN(FirstName)) AS FirstName, MAX(LEN(Email)) AS Email,
       MAX(LEN(Phone)) AS Phone, MAX(LEN(Gender)) AS Gender
FROM Contact.ContactImport;

SELECT MAX(ContactId) AS MaxContactId, MAX(PostalAddressId) AS MaxPostalAddressId,
       MAX(CompanyId) AS MaxCompanyId,
       SUM(CASE WHEN CAST(BirthDate AS time) <> '00:00' THEN 1 ELSE 0 END) AS DatesWithTime
FROM Contact.ContactImport;

SELECT Title, Gender, COUNT(*) AS Contacts
FROM Contact.ContactImport
GROUP BY Title, Gender
ORDER BY Title, Gender;
GO
-- 2. The closest types. The strings stay in varchar: the data is Latin. The keys stay int,
--    the type of the keys they reference in Contact.Contact, Contact.Address and
--    Contact.Company. The lengths keep a margin over what is stored today.
CREATE TABLE Contact.ContactClean (
    ContactId       int          NOT NULL CONSTRAINT pk_ContactClean PRIMARY KEY,
    Title           varchar(3)   COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    LastName        varchar(50)  COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
    FirstName       varchar(50)  COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    Email           varchar(150) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    Phone           varchar(15)  COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    Gender          char(1)      COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
    PostalAddressId int          NOT NULL,
    CompanyId       int          NULL,
    BirthDate       date         NULL
);
INSERT INTO Contact.ContactClean (ContactId, Title, LastName, FirstName, Email, Phone,
                                  Gender, PostalAddressId, CompanyId, BirthDate)
SELECT ContactId, Title, LastName, FirstName, Email, RTRIM(Phone), RTRIM(Gender),
       PostalAddressId, CompanyId, BirthDate
FROM Contact.ContactImport;

CREATE INDEX nix_contactclean_email ON Contact.ContactClean (Email);
GO
-- 3. The pages of the two tables and of their index on Email.
SELECT OBJECT_NAME(ps.object_id) AS TableName, i.name AS IndexName,
       ps.row_count, ps.used_page_count
FROM sys.dm_db_partition_stats AS ps
JOIN sys.indexes AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.object_id IN (OBJECT_ID(N'Contact.ContactImport'), OBJECT_ID(N'Contact.ContactClean'))
ORDER BY TableName, ps.index_id;
GO
-- 4. The lookup by e-mail, the string sent in nvarchar(4000) as .NET and JDBC do by
--    default. On Contact.ContactImport the column is nvarchar: a seek. On
--    Contact.ContactClean the varchar column, in a SQL collation, is converted row by row,
--    and its index is read in full: the plan shows the PlanAffectingConvert warning.
SET STATISTICS IO ON;
EXEC sys.sp_executesql
    N'SELECT ContactId, LastName, FirstName FROM Contact.ContactImport WHERE Email = @Email;',
    N'@Email nvarchar(4000)', @Email = N'a.aba@institut-trefois.fr';
EXEC sys.sp_executesql
    N'SELECT ContactId, LastName, FirstName FROM Contact.ContactClean WHERE Email = @Email;',
    N'@Email nvarchar(4000)', @Email = N'a.aba@institut-trefois.fr';
-- 5. The fix on the client side: the parameter in the type of the column.
EXEC sys.sp_executesql
    N'SELECT ContactId, LastName, FirstName FROM Contact.ContactClean WHERE Email = @Email;',
    N'@Email varchar(150)', @Email = 'a.aba@institut-trefois.fr';
SET STATISTICS IO OFF;
GO
-- Cleanup.
DROP TABLE Contact.ContactClean;
DROP TABLE Contact.ContactImport;
GO
