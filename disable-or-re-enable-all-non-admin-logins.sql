/*
 *	Disable non-admin user access to site; users without access prior to this script will be copied into a temporary table so that re-enabling users can filter out previously disabled logins.
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; -- set @saveChanges = 1
declare @disabled bit;
-- Set to Disable
set @disabled = 1;
-- Uncomment below to re-enable
-- set @disabled = 0
declare @supportedVersions varchar(1000); select @supportedVersions='16.*'

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

-- Disable
if (@disabled = 1)
begin
	-- Create table and store previously disabled logins
	if not exists (select * from INFORMATION_SCHEMA.TABLES where TABLE_NAME = N'temp_previously_disabled_logins')
	begin
		create table temp_previously_disabled_logins (
			ID int
		);
		select @rowcount=@@ROWCOUNT, @error=@@ERROR
		if @error<>0 goto ERR
		raiserror('temp_previously_disabled_logins table created', 0, 1, @rowcount) with nowait
	end

	if not exists (select ID from temp_previously_disabled_logins)
	begin
		insert into temp_previously_disabled_logins select ID from Login where IsLoginDisabled = 1;
		select @rowcount=@@ROWCOUNT, @error=@@ERROR
		if @error<>0 goto ERR
		raiserror('%d disabled users backed up to temp_previously_disabled_logins', 0, 1, @rowcount) with nowait
	end
	-- Set all non-admin logins to be disabled.
	update Login set IsLoginDisabled = 1 where exists
		(select l.ID from Login l join Member_Now on Member_Now.ID = l.ID where Login.ID = l.ID and Member_Now.DefaultRoleID <> 1);
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d users disabled', 0, 1, @rowcount) with nowait
end

-- Re-enable
if (@disabled = 0)
begin
	update Login set IsLoginDisabled = 0 where exists
		(select l.ID from Login l join Member_Now on Member_Now.ID = l.ID where Login.ID = l.ID and Member_Now.DefaultRoleID <> 1)
	and not exists
		(select ID from temp_previously_disabled_logins t where t.ID = Login.ID);
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d users re-enabled', 0, 1, @rowcount) with nowait

	drop table temp_previously_disabled_logins;
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('temp_previously_disabled_logins table dropped', 0, 1, @rowcount) with nowait
end


if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE:
