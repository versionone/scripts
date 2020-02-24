/*
 *	Restore deleted teamroom
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @teamroomId int;
select @teamroomId = 3142;
---------

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

declare @str int, @auditid int
exec _SaveString 'Restore deleted teamroom', @str output

insert dbo.[Audit]([ChangeDateUTC],[ChangedByID],[ChangeReason],[ChangeComment])
values(GETUTCDATE(),null,@str,null)

select @auditid=SCOPE_IDENTITY()

update dbo.Room_Now set AssetState = 64, AuditBegin = @auditid where ID = @teamroomId


----------
/* after every modifying statement, check for errors; optionally, emit status */
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' teamroom updated'


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: