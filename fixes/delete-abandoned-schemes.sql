/*	
 *	Delete abandoned schemes.
 *
 * Due to defects  D-07462 and D-06870, an instance of VersionOne Core 11.3 can become unusable,
 * always displaying an error like:
 *
 * StructureMap Exception Code: 207 
 * Internal exception while creating Instance '4bacb5fe-5c9a-4b9d-adf2-114846217e8a' of PluginType VersionOne.Visibility.IVizConfigChecker, VersionOne, Version=11.3.4.95, Culture=neutral, PublicKeyToken=e0f410c10d2e7630. Check the inner exception for more details. 
 * An item with the same key has already been added.
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @supportedVersions varchar(1000); select @supportedVersions='11.3.*'

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
-----------
declare @changeReason int, @changeComment int
exec dbo._SaveString 'D-07462', @changeReason out
exec dbo._SaveString 'remove abandoned schemes', @changeComment out

declare @audit int
insert dbo.Audit(ChangeDateUTC, ChangeReason, ChangeComment) values(GetUTCDate(), @changeReason, @changeComment)
select @audit=SCOPE_IDENTITY()

declare @schemeIDs table(ID int)

update dbo.Scheme_Now
set AuditBegin=@audit, AssetState=255
output DELETED.ID into @schemeIDs
where ID not in (select SchemeID from Scope_Now)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d abandoned schemes deleted', 0, 1, @rowcount) with nowait

delete AttributeDefinitionVisibility
from @schemeIDs S
where S.ID=SchemeID

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d abandoned AttributeDefinition visibility records deleted', 0, 1, @rowcount) with nowait
-----------
if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE:
