 /*
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
if (select count(*) from dbo.[Counter])=8000
begin
	begin tran; save tran TX
	insert into dbo.Counter (Value)
	select Value + 8000 from dbo.Counter;

	if @@ERROR<>0 goto ERR

	if (@saveChanges = 1) goto OK
	raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
	ERR: rollback tran TX
	OK: commit
end
