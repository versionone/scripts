/*	
 *	Restore 'System Admin' privileges to the admin member (Member:20)
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @error int, @rowcount int
set nocount on; begin tran; save tran TX

declare @str int, @auditid int
exec dbo._SaveString 'make-admin-admin', @str output

insert dbo.[Audit]([ChangeDateUTC],[ChangedByID],[ChangeReason],[ChangeComment])
values(GETUTCDATE(),null,@str,null)

select @auditid=SCOPE_IDENTITY()

delete from dbo.ScopeMemberACL where MemberID=20
insert into dbo.ScopeMemberACL(ScopeID, MemberID, RoleID, Owner) values (0, 20, 1, 1)

exec dbo.Security_GenerateEffectiveACL 0, 20

update dbo.Member_Now set AuditBegin=@auditid, DefaultRoleID=1 where ID=20

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d Member record given admin privileges', 0, 1, @rowcount) with nowait


if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE:
