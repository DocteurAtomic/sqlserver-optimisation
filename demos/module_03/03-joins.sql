-- Clip 3.3: the three join algorithms, and a join chosen on a wrong estimate. Runs on the
-- lab, in one session. Reads only. Turn on the actual plan in SSMS (Ctrl+M).
USE PachadataTraining;
GO
SET STATISTICS IO, TIME ON;
GO
-- 1. Nested Loops: the payments of one day (15 rows), each one looked up in the invoices
--    by the key of their clustered index.
SELECT p.PaymentId, p.PaymentDate, p.Amount, i.InvoiceDate, i.GrossAmount
FROM Enrollment.Payment AS p
JOIN Enrollment.Invoice AS i ON i.InvoiceCode = p.InvoiceCode
WHERE p.PaymentDate = '20260915';
GO
-- 2. Merge Join: all the invoices and their lines. Both clustered indexes start with
--    InvoiceCode, so both inputs arrive sorted on the join column.
SELECT i.InvoiceCode, i.InvoiceDate, l.LineNumber, l.Label, l.NetAmount
FROM Enrollment.Invoice AS i
JOIN Enrollment.InvoiceLine AS l ON l.InvoiceCode = i.InvoiceCode;
GO
-- 3. Hash Match: the 107,994 deliveries of the November 2024 newsletter (campaign 14), with
--    the name of each recipient. Neither input is sorted on ContactId.
SELECT c.LastName, c.FirstName, d.SendDate, d.Opened, d.Clicked
FROM Marketing.Delivery AS d
JOIN Contact.Contact AS c ON c.ContactId = d.ContactId
WHERE d.CampaignId = 14;
GO
-- 4. The same query, the campaign in a local variable: the optimizer cannot see its value
--    when it compiles, and estimates the average number of deliveries per campaign.
DECLARE @CampaignId int = 14;
SELECT c.LastName, c.FirstName, d.SendDate, d.Opened, d.Clicked
FROM Marketing.Delivery AS d
JOIN Contact.Contact AS c ON c.ContactId = d.ContactId
WHERE d.CampaignId = @CampaignId;
GO
-- Where the estimate comes from: rows of the table divided by the number of campaigns.
SELECT COUNT(*) AS Deliveries, COUNT(DISTINCT CampaignId) AS Campaigns,
       CAST(1.0 * COUNT(*) / COUNT(DISTINCT CampaignId) AS decimal(10, 2)) AS AveragePerCampaign
FROM Marketing.Delivery;
GO
SET STATISTICS IO, TIME OFF;
GO
