DECLARE @number int
DECLARE @assetID int
DECLARE @assetType varchar(100)
DECLARE @saveChanges bit -- set @saveChanges = 1


SET @number = 0000
SET @assetType = 'AssetType'

SELECT @assetID = ID
FROM [dbo].[Workitem_Now]
WHERE Number = @number AND AssetType = @assetType

BEGIN TRAN; SAVE TRAN TX

UPDATE [dbo].[LongString]
SET [Value] = N'new value'
WHERE ID IN (SELECT [Description] FROM [dbo].[BaseAsset] WHERE ID = @assetID)

UPDATE [dbo].[String]
SET [Value] = N'new value'
WHERE ID IN (SELECT [Name] FROM [dbo].[BaseAsset] WHERE ID = @assetID)

IF @saveChanges=1 GOTO OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: ROLLBACK TRAN TX
OK: COMMIT
