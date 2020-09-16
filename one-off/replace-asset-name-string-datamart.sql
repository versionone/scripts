/*
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1

declare @error int, @rowcount int
set nocount on; begin tran; save tran TX

UPDATE Dim.PrimaryWorkitem
SET PrimaryWorkitemName = N'new value'
WHERE PrimaryWorkitemDisplayId = 'D-00000'

/* after every modifying statement, check for errors; optionally, emit status */
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d row/s uptated to "new value"', 0, 1, @rowcount) with nowait


if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE:
