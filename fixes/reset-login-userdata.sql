/*
 *  Reset a user's Login.UserData, which may have been corrupted by a
 *  race condition when saving bad ESON into the user's space.
 *
 *  NOTE: Be sure to set the @username variable below. This is the
 *        name they use to log into the system.
 *
 *  NOTE: This script defaults to rolling back changes.
 *        To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @supportedVersions varchar(1000); select @supportedVersions='10.2.*, 10.3.*, 11.*, 12.*, 13.*, 14.*, 15.*, 16.*, 17.*, 18.0'
declare @username varchar(1000); set @username = 'USERNAME-GOES-HERE'

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

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

update Login set UserData = null where Username = @username

/* after every modifying statement, check for errors; optionally, emit status */
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' Login.UserData reset'


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:
