/*	
 *	Remove Vertical Tab (ASCII 11) characters from String values.
 *	This does not fix LongString content!
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1

declare @error int, @rowcount int
set nocount on; begin tran; save tran TX

update String
set Value=REPLACE(Value, CHAR(11), '')
where Value like '%' + CHAR(11) + '%'

/* after every modifying statement, check for errors; optionally, emit status */
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('vertical-tab characters removed from %d strings', 0, 1, @rowcount) with nowait


if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE: