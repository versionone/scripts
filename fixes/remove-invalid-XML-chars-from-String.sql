/*	
 *	Remove NUL characters (ASCII 0) and Vertical Tab (ASCII 11) characters from String values.
 *
 *	NOTE: This updates strings in situ!
 *
 *	NOTE: This does not fix LongString content!
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

NULLOOP:
update String set Value=cast(substring(HexValue, 1+0, N*2)+substring(HexValue, 1+(N+1)*2, datalength(HexValue)-(N+1)*2) as nvarchar(4000))
from (
	select String.ID, String.Value, HexValue=cast(String.Value as varbinary(max)), N=Counter.Value, C=substring(cast(String.Value as varbinary(max)), 1+Counter.Value*2, 2)
	from String
	join Counter on Counter.Value<len(String.Value)
)_
where C=0x0000 and String.ID=_.ID

/* after every modifying statement, check for errors; optionally, emit status */
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('NUL characters removed from %d strings', 0, 1, @rowcount) with nowait
if @rowcount>0 goto NULLOOP

if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE: