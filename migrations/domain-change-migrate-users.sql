/*	
 *	Customer-facing SQL script template
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; set @saveChanges = 1
declare @oldDomain nvarchar(100); set @oldDomain = 'Old Domain Name' -- set this to the old domain name that is being replaced
declare @newDomain nvarchar(100); set @newDomain = 'New Domain Name' -- set this to your new domain name
declare @supportedVersions varchar(1000); select @supportedVersions='10.2.*, 10.3.*, 11.*, 15.*, 16.*, 17.*'

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

declare @Usernames table(ID int, originalUserName nvarchar(100), newUserName nvarchar(100) collate Latin1_General_BIN2 not null)
INSERT @Usernames 
SELECT ID, Username as originalUserName, 
	@newDomain + '\' + substring(Username, charindex('\', Username)+1, len(Username)-1) as newUserName
	FROM Login
	WHERE Username like '%\%'
	AND substring(Username, 0, charindex('\', Username)) = @oldDomain

UPDATE Login
	SET Login.Username = u.newUserName
	FROM @Usernames as u
	WHERE Login.ID=u.ID

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d Usernames updated', 0, 1, @rowcount) with nowait

if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)

ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE: