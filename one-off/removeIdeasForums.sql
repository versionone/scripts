/*	
 *	Remove all Ideas forums other than the default and place any ideas in those into the other category
 *	(run against ideas instance db)
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1


declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

UPDATE [Idea] 
   SET [Category_id] = 1
where Category_id in ( select id from category where Forum_id <>1)

delete Category where forum_id <>1

delete from claim where forum_id <> 1
delete forum where id <>1


/* after every modifying statement, check for errors; optionally, emit status */
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:


