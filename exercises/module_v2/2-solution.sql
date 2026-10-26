-- Exercise of module V2, solution. Runs on the lab, in one session, after 1-start.sql.
-- Part 1: the history of a contact, covered by the index it already uses. Part 2: a filtered
-- index for the clicks of a campaign, and the procedure rewritten so that it can use it.
-- Part 3: the log a newsletter writes, with the indexes as delivered and with yours.
-- The indexes and the procedure stay changed; 00-setup.sql of the next module restores the
-- database. The reads quoted were measured on the lab (SORTIES.md of the module); they
-- repeat to a few pages.
USE PachadataTraining;
SET NOCOUNT ON;
SET ARITHABORT ON;
GO
-- The newsletter of October 2026, for this script only: 107,994 e-mails recorded in one
-- statement, inside a transaction rolled back at the end. It returns the log written, and
-- the pages of each index before and after. The rollback removes the rows, not the page
-- splits: an index that had to split its pages keeps them half empty.
CREATE OR ALTER PROCEDURE #Newsletter
    @Label varchar(20)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @log bigint;
    DECLARE @pages TABLE (step varchar(10), index_id int, pages bigint);
    INSERT INTO @pages SELECT 'before', index_id, SUM(used_page_count)
    FROM sys.dm_db_partition_stats WHERE object_id = OBJECT_ID(N'Marketing.Delivery')
    GROUP BY index_id;
    BEGIN TRANSACTION;
    INSERT INTO Marketing.Campaign (CampaignId, CampaignType, Name, SendDate, SessionId)
    VALUES (100000, 'Letter', 'Lettre PachaData octobre 2026', '20261006', NULL);
    INSERT INTO Marketing.Delivery (CampaignId, ContactId, SendDate, Opened, Clicked)
    SELECT 100000, ContactId, DATEADD(day, 35, SendDate), 0, 0
    FROM Marketing.Delivery WHERE CampaignId = 36;
    SELECT @log = database_transaction_log_bytes_used FROM sys.dm_tran_database_transactions
    WHERE transaction_id = CURRENT_TRANSACTION_ID() AND database_id = DB_ID();
    ROLLBACK TRANSACTION;
    INSERT INTO @pages SELECT 'after', index_id, SUM(used_page_count)
    FROM sys.dm_db_partition_stats WHERE object_id = OBJECT_ID(N'Marketing.Delivery')
    GROUP BY index_id;
    SELECT @Label AS Indexes, @log AS LogBytes;
    SELECT @Label AS Indexes, i.name AS IndexName, b.pages AS PagesBefore, a.pages AS PagesAfter
    FROM @pages AS b
    JOIN @pages AS a ON a.index_id = b.index_id AND a.step = 'after'
    JOIN sys.indexes AS i ON i.object_id = OBJECT_ID(N'Marketing.Delivery') AND i.index_id = b.index_id
    WHERE b.step = 'before'
    ORDER BY b.index_id;
END;
GO
-- Part 3, before: the newsletter with the indexes as delivered.
EXEC #Newsletter @Label = 'as delivered';
GO

-- Part 1.
-- 1. The history of contact 1234: an Index Seek in ix_Delivery_ContactId, then one Key
--    Lookup per e-mail in pk_Delivery (three levels), and a Sort on SendDate. About 120 to
--    200 reads for 36 rows, depending on the plan in the cache.
SET STATISTICS IO ON;
EXEC Marketing.GetContactDeliveries @ContactId = 1234;
-- 2. The leaf of ix_Delivery_ContactId holds ContactId and DeliveryId, the key of the
--    clustered index: a query that reads only these two needs no lookup.
SELECT DeliveryId FROM Marketing.Delivery WHERE ContactId = 1234;
SET STATISTICS IO OFF;
GO
-- 3. The same index, with SendDate in the key (the page sorts on it) and the other columns
--    in INCLUDE. DROP_EXISTING: no second index on ContactId, and no moment without one.
CREATE INDEX ix_Delivery_ContactId ON Marketing.Delivery (ContactId, SendDate)
    INCLUDE (CampaignId, Opened, Clicked)
    WITH (DROP_EXISTING = ON);
GO
-- 4. After: one Index Seek, read backwards, no Key Lookup and no Sort.
SET STATISTICS IO ON;
EXEC Marketing.GetContactDeliveries @ContactId = 1234;
SET STATISTICS IO OFF;
GO

-- Part 2.
-- 5. The clicks of campaign 36: 4,329 rows out of 107,994. ix_Delivery_CampaignId would
--    need 107,994 lookups to check Clicked; the optimizer scans the clustered index instead,
--    in parallel (about 9,900 reads).
SET STATISTICS IO ON;
EXEC Marketing.GetCampaignDeliveries @CampaignId = 36, @Clicked = 1;
SET STATISTICS IO OFF;
GO
-- 6. A filtered index on the clicked e-mails only: 228,742 rows out of 4 million.
CREATE INDEX ix_Delivery_Clicked ON Marketing.Delivery (CampaignId)
    INCLUDE (ContactId, SendDate)
    WHERE Clicked = 1;
GO
SELECT i.name AS IndexName, i.filter_definition, SUM(p.used_page_count) AS Pages,
       SUM(p.row_count) AS Rows
FROM sys.indexes AS i
JOIN sys.dm_db_partition_stats AS p ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'Marketing.Delivery')
GROUP BY i.index_id, i.name, i.filter_definition
ORDER BY i.index_id;
GO
-- 7. The procedure still scans: its plan must be right for @Clicked = 0 as well, and the
--    filtered index holds no row with Clicked = 0. The plan shows the warning
--    UnmatchedIndexes. Recompiling does not help: the value is a parameter.
EXEC sys.sp_recompile N'Marketing.GetCampaignDeliveries';
GO
SET STATISTICS IO ON;
EXEC Marketing.GetCampaignDeliveries @CampaignId = 36, @Clicked = 1;
SET STATISTICS IO OFF;
GO
-- 8. The fix: one branch per value, each one with the value written in the query. The
--    branch of the clicks matches the filter of the index; the other one keeps the plan it
--    had.
CREATE OR ALTER PROCEDURE Marketing.GetCampaignDeliveries
    @CampaignId int,
    @Clicked    bit
AS
BEGIN
    SET NOCOUNT ON;
    IF @Clicked = 1
        SELECT DeliveryId, ContactId, SendDate
        FROM Marketing.Delivery
        WHERE CampaignId = @CampaignId
          AND Clicked = 1;
    ELSE
        SELECT DeliveryId, ContactId, SendDate
        FROM Marketing.Delivery
        WHERE CampaignId = @CampaignId
          AND Clicked = 0;
END;
GO
SET STATISTICS IO ON;
EXEC Marketing.GetCampaignDeliveries @CampaignId = 36, @Clicked = 1;
SET STATISTICS IO OFF;
GO

-- Part 3, after: the same newsletter, with the covering index of part 1 and the filtered
-- index of part 2. The new e-mails all have Clicked = 0: none goes into the filtered index.
-- The covering index of part 1 is wider than the one it replaces, and its key starts with
-- ContactId: the new rows go in the middle of the index, one per contact, and its pages,
-- full after DROP_EXISTING, split.
EXEC #Newsletter @Label = 'yours';
GO
