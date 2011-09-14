/*	
 *	This script deletes some views that are commonly converted into tables
 *	when DTS or SSIS is used to copy a database.  Such a situation keeps 
 *	Setup from upgrading the database successfully.
 *	
 */
IF OBJECTPROPERTY(OBJECT_ID('dbo._DropTable'), 'IsProcedure')=1 DROP PROC dbo._DropTable
GO
CREATE PROC dbo._DropTable
(
	@objectname sysname
) AS
DECLARE @id int
SET @id = OBJECT_ID(@objectname)
IF @id IS NOT NULL
BEGIN
	DECLARE @sql nvarchar(1000)

	IF OBJECTPROPERTY(@id, 'IsUserTable') = 1
		SET @sql = 'DROP TABLE ' + @objectname
	ELSE
		PRINT @objectname + ' is not a Table'

	IF @sql IS NOT NULL begin
		PRINT @sql
		EXEC(@sql)
	end
END
GO

declare @saveChanges bit; set @saveChanges = 1

-- Ensure the correct database version
set nocount on; begin tran; save tran TX

exec _DropTable 'WorkitemAllocations_Now'
exec _DropTable 'WorkitemAllocations'
exec _DropTable 'AssetAuditWithPrior'
exec _DropTable 'AssetAuditWithNext'
exec _DropTable 'AssetAuditWithNext_Now'
exec _DropTable 'CreationAssetAudit'

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:
GO
DROP PROC dbo._DropTable
