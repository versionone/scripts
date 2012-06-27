/*	
 *	Turn off Roadmapping integration if you cannot reach the configuration page
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @supportedVersions varchar(1000); select @supportedVersions='10.2.*, 10.3.*, 11.*'

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



declare @feature_name varchar(50), @value varchar(50)
select @feature_name = 'Roadmapping.Enabled', @value = 'False'

if (exists(select * from SystemConfig where Name = @feature_name)) 
begin
	update dbo.SystemConfig set Value=@value where Name=@feature_name
	print 'Updated ' + @feature_name + ' in SystemConfig to be ' + @value
end
else
begin
	insert dbo.SystemConfig(Value, Name) values (@value, @feature_name)
	print 'Inserted ' + @value + ' into SystemConfig for ' + @feature_name
end



/* after every modifying statement, check for errors; optionally, emit status */
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: