/*	
 *	Consolidates lDescription field history records.
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @error int, @rowcount int
set nocount on; begin tran; save tran TX

DECLARE @toRemove TABLE(
	[ID] [int] NOT NULL,
	[AssetType] [varchar](100) COLLATE Latin1_General_BIN NOT NULL,
	[AuditBegin] [int] NOT NULL)  
INSERT INTO @toRemove
SELECT Main.ID, Main.AssetType, Main.AuditBegin
FROM
( SELECT BA.ID, BA.[AssetType],BA.[AuditBegin],BA.[AuditEnd],BA.[Description], A.ChangedByID, A.[ChangeDateUTC]
  ,LEAD([ChangedByID]) OVER (ORDER BY A.[ChangeDateUTC]) AS NextUserID
  FROM [BaseAsset] BA
  JOIN [Audit] A ON A.ID = BA.AuditBegin 
) AS Main
LEFT JOIN (
	SELECT *
	FROM (
	SELECT BA.ID,BA.[AssetType],BA.[AuditBegin],BA.[AuditEnd],BA.[Description],A.[ChangeDateUTC],A.[ChangedByID]
		  ,LEAD([ChangedByID]) OVER (PARTITION BY BA.ID, BA.AssetType ORDER BY A.[ChangeDateUTC]) AS NextUserID
		  ,LEAD([ChangeDateUTC]) OVER (PARTITION BY BA.ID, BA.AssetType, [ChangedByID] ORDER BY A.[ChangeDateUTC]) AS NextChangeUTC
		  ,LEAD(BA.[Description]) OVER (PARTITION BY BA.ID, BA.AssetType ORDER BY A.[ChangeDateUTC]) AS NextDescriptionID
		  ,LAG(BA.[Description]) OVER (PARTITION BY BA.ID, BA.AssetType ORDER BY A.[ChangeDateUTC]) AS PreviousDescriptionID
	  FROM [BaseAsset] BA
	  JOIN [Audit] A ON A.ID = BA.AuditBegin) AS BaseQuery
	WHERE 
	ISNULL(NextUserID,-1) = [ChangedByID] -- Consecutive changes from the same user
	AND 
	DATEDIFF(mi,[ChangeDateUTC],NextChangeUTC) < 5 --Time threshold / period / lapse.
	AND (
		ISNULL(NextDescriptionID,-1) != ISNULL([Description],-1) --Description has changed
		AND
		ISNULL(PreviousDescriptionID,-1) != ISNULL([Description],-1) --Description has changed
	)
) AS ToRemove on Main.AuditBegin = ToRemove.AuditBegin AND Main.ID = ToRemove.ID
WHERE NOT ToRemove.AuditBegin IS NULL
ORDER BY ID, AssetType,Main.AuditBegin
update dbo.[BaseAsset]
set AuditEnd=NewAuditEnd
FROM (
SELECT *
FROM (
	SELECT Main.ID, Main.AssetType, Main.AuditBegin, Main.AuditEnd, LEAD(Main.AuditBegin) OVER (PARTITION BY Main.ID, Main.AssetType ORDER BY Main.ChangeDateUTC) NewAuditEnd
	FROM
	( SELECT BA.ID, BA.[AssetType],BA.[AuditBegin],BA.[AuditEnd],BA.[Description], A.ChangedByID, A.[ChangeDateUTC]
	  ,LEAD([ChangedByID]) OVER (ORDER BY A.[ChangeDateUTC]) AS NextUserID
	  FROM [BaseAsset] BA
	  JOIN [Audit] A ON A.ID = BA.AuditBegin 
	) AS Main
	LEFT JOIN (
		SELECT *
		FROM (
		SELECT BA.ID,BA.[AssetType],BA.[AuditBegin],BA.[AuditEnd],BA.[Description],A.[ChangeDateUTC],A.[ChangedByID]
			  ,LEAD([ChangedByID]) OVER (PARTITION BY BA.ID, BA.AssetType ORDER BY A.[ChangeDateUTC]) AS NextUserID
			  ,LEAD([ChangeDateUTC]) OVER (PARTITION BY BA.ID, BA.AssetType, [ChangedByID] ORDER BY A.[ChangeDateUTC]) AS NextChangeUTC
			  ,LEAD(BA.[Description]) OVER (PARTITION BY BA.ID, BA.AssetType ORDER BY A.[ChangeDateUTC]) AS NextDescriptionID
			  ,LAG(BA.[Description]) OVER (PARTITION BY BA.ID, BA.AssetType ORDER BY A.[ChangeDateUTC]) AS PreviousDescriptionID
		  FROM [BaseAsset] BA
		  JOIN [Audit] A ON A.ID = BA.AuditBegin) AS BaseQuery
		WHERE 
		ISNULL(NextUserID,-1) = [ChangedByID] -- Consecutive changes from the same user
		AND 
		DATEDIFF(mi,[ChangeDateUTC],NextChangeUTC) < 5 --Time threshold / period / lapse.
		AND (
			ISNULL(NextDescriptionID,-1) != ISNULL([Description],-1) --Description has changed
			AND
			ISNULL(PreviousDescriptionID,-1) != ISNULL([Description],-1)
		)
	) AS ToRemove on Main.AuditBegin = ToRemove.AuditBegin AND Main.ID = ToRemove.ID
	WHERE ToRemove.AuditBegin IS NULL) as ToUpdate
WHERE 
NOT NewAuditEnd IS NULL
AND AuditEnd != NewAuditEnd
) AS Core
WHERE 
[BaseAsset].ID = Core.ID 
AND [BaseAsset].AssetType = Core.AssetType 
AND [BaseAsset].[AuditBegin] = Core.[AuditBegin]
AND Core.AuditEnd != Core.NewAuditEnd 
DELETE BA
FROM [BaseAsset] BA
JOIN @toRemove TR ON BA.ID = TR.ID AND BA.AssetType = TR.AssetType AND BA.AuditBegin = TR.AuditBegin
DELETE AA
FROM [AssetAudit] AA
JOIN @toRemove TR ON AA.ID = TR.ID AND AA.AssetType = TR.AssetType AND AA.AuditID = TR.AuditBegin
DELETE A
FROM [Audit] A
JOIN @toRemove TR ON A.ID = TR.AuditBegin


if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE:
