/*
 *  This script is to be used when you change your server DNS/Domain name or the V1 App Name (or both).
 *  The OldServerSlug is whatever your previous server/appname value used to be and NewServerSlug is whatever your
 *  new server/appname is.
 *  
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */

declare @saveChanges bit; --set @saveChanges = 1
declare @supportedVersions varchar(1000); select @supportedVersions='10.2.*, 10.3.*, 11.*, 12.*, 13.*, 14.*, 15.*, 16.*, 17.*, 18.*'

-- Ensure the correct database version
BEGIN
	declare @sep char(2); select @sep=', '
	if not exists(select *
		from dbo.SystemConfig
		join (
		select SUBSTRING(@supportedVersions, C.Value+1, CHARINDEX(@sep, @supportedVersions+@sep, C.Value+1)-C.Value-1) as Value
		from dbo.Counter C
		where C.Value < DataLength(@supportedVersions) and SUBSTRING(@sep+@supportedVersions, C.Value+1, DataLength(@sep)) = @sep
		) Version on SystemConfig.Value like REPLACE(Version.Value, '*', '%') and SystemConfig.Name = 'Version'
	) begin
			raiserror('Only supported on version(s) %s',16,1, @supportedVersions)
			goto DONE
	end
END

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
