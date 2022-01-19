/*
 *  This script is to be used when you change your server DNS/Domain name or the V1 App Name (or both).
 *  The OldServerSlug is whatever your previous server/appname value used to be and NewServerSlug is whatever your
 *  new server/appname is.
 *  
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */

declare @saveChanges bit; --set @saveChanges = 1

if not exists (select * from INFORMATION_SCHEMA.COLUMNS where 
	TABLE_SCHEMA='dbo' and 
	TABLE_NAME='LongString' and 
	COLUMN_NAME='Value'
) begin
	raiserror('Unsupported database',16,1)
	goto DONE
end

declare @error int, @rowcount int
set nocount on; begin tran; save tran TX

DECLARE @OldServerSlug nvarchar(max)
DECLARE @NewServerSlug nvarchar(max)

SET @OldServerSlug = 'https://www.oldV1host.com/VersionOne.Web/'
SET @NewServerSlug = 'http://www.newV1host.com/V1.Web/'

UPDATE [dbo].[LongString]
SET [Value] = REPLACE(cast([Value] as nvarchar(max)), @OldServerSlug, @NewServerSlug)
WHERE [Value] like '%' + @OldServerSlug + '%'

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d records updated', 0, 1, @rowcount) with nowait

if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE:
