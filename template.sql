/*	
 *	Customer-facing SQL script template
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @supportedVersion varchar(10); set @supportedVersion = '10.2'

-- Ensure the correct database version
if (@supportedVersion is not null) begin
	if not exists (select * from SystemConfig where Name='Version' and Value like @supportedVersion + '.%') begin
		raiserror('This script can only run on a %s VersionOne database',16,1, @supportedVersion)
		goto DONE
	end
end

set nocount on; begin tran; save tran TX


/* script code goes here */


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: