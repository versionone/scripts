/*	
 *	For cases when Taskboard shows non-stardard column widths per user.
 * 
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */

declare @saveChanges bit; --set @saveChanges = 1

declare @error int, @rowcount int
set nocount on; begin tran; save tran TX

create table #T(Path varbinary(400) not null primary key)
insert into #T exec dbo.Profile_PathsByWildcard '/user/*/Gadgets/TeamRoom/TaskBoard/Widths'

select dbo.Profile_PathBinToStr(ProfileValue.Path), Value 
from dbo.ProfileValue
join #T T on ProfileValue.Path=T.Path 
where Value like '%px'

delete dbo.ProfileValue 
from #T T 
where ProfileValue.Path=T.Path and Value like '%px'
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d ProfileValues deleted', 0, 1, @rowcount) with nowait

drop table #T

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: