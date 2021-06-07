/*	
 *	Reset config value manualTarget2 to working key (manualTarget)
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1


declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

UPDATE [Config]
SET Value=JSON_MODIFY(
  JSON_MODIFY(Value,'$.manualTarget', CAST(JSON_VALUE(Value,'$.manualTarget2') AS varchar)),
  '$.manualTarget2',
  NULL
 )
WHERE Value like '%manualTarget2%'


/* after every modifying statement, check for errors; optionally, emit status */
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:


