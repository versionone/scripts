
/*	
 *	Reset all user's passwords to 'password'
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1

set nocount on; begin tran; save tran TX


update Login 
set PasswordHash=0x04104992C230B55875FA684E9FC8237B32837E1C35 -- 'password'

if @@ERROR<>0 goto ERR


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: