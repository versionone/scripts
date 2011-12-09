/*
 *    Clear out the IdeasUserCache for the VersionOne Admin
 *    account (Member 20).
 *
 *    NOTE: This script defauts to rolling back changes.
 *          To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

declare @memberId int
select @memberId = 20
delete from IdeasUserCache where MemberID = @memberId
delete from IdeasUserCache_Now where MemberID = @memberId

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print 'IdeasUserCache cleared for MemberID = ' + @memberId

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:

