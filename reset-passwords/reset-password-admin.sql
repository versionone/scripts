/*	
 *	Reset original admin's password to 'admin'
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1

set nocount on; begin tran; save tran TX


update Login 
set PasswordHash=0x0437373325976655A750627948DEB21B5CD954764A  -- 'admin'
where ID=20

if @@ERROR<>0 goto ERR


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: