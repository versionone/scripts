/*	
 *	Customer-facing SQL script template
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1

-- Ensure the correct database version
declare @supportedVersion varchar(10); set @supportedVersion = '10.2'
if (@supportedVersion is not null) begin
	if not exists (select * from SystemConfig where Name='Version' and Value like @supportedVersion + '.%') begin
		raiserror('This script can only run on a %s VersionOne database',16,1, @supportedVersion)
		goto DONE
	end
end

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX


/* 
	script code goes here 
*/

/* after every modifying statement, check for errors; optionally, emit status */
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' foobars blah-blahed'


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: