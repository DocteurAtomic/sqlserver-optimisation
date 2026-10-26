-- Module V2, setup. Runs on the lab, in one session, before the first clip of the module.
-- It lasts a few seconds.
-- 1. Restores PachadataTraining as delivered, at compatibility level 170.
-- 2. The problem of the module: the customer area of the website gets a page that lists the
--    invoices of a company, and the developer ships it with the procedure
--    Enrollment.GetCompanyInvoices and the index he wrote for it, nix_invoice_companyid,
--    whose key is CompanyId alone. The index finds the invoices of the company, but holds
--    none of the columns the page shows: each invoice found goes back to the clustered index
--    by a Key Lookup, three pages read per invoice. Called a few hundred times a minute, the
--    page reads ten to a hundred times the pages it needs. Clip V2.4 tells it, and measures
--    the index that covers the query.
-- 3. The first call of the day, for company 100 (10 invoices): the plan of the procedure is
--    compiled for a company of usual size, and stays in the cache. SET ARITHABORT ON makes
--    this session match SSMS: a different value would compile a separate plan.
-- charge.sh then sends the page in a loop, for random companies.
USE master;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
CREATE INDEX nix_invoice_companyid ON Enrollment.Invoice (CompanyId);
GO
CREATE OR ALTER PROCEDURE Enrollment.GetCompanyInvoices
    @CompanyId int
AS
BEGIN
    SET NOCOUNT ON;
    SELECT InvoiceCode, InvoiceDate, DueDate, GrossAmount, ReminderLevel
    FROM Enrollment.Invoice
    WHERE CompanyId = @CompanyId
    ORDER BY InvoiceDate DESC;
END;
GO
SET ARITHABORT ON;
EXEC Enrollment.GetCompanyInvoices @CompanyId = 100;
GO
SELECT i.name AS IndexName, i.type_desc AS IndexType
FROM sys.indexes AS i
WHERE i.object_id = OBJECT_ID(N'Enrollment.Invoice')
ORDER BY i.index_id;
