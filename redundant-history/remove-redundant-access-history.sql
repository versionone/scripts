/*	
 *	Remove duplicate Access records that occur on the same day.
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1

BEGIN
	if not exists (select * from INFORMATION_SCHEMA.TABLES where TABLE_NAME='Access') begin
		raiserror('No such table [Access]',16,1)
		goto DONE
	end
END

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

delete Access
from (
	select ID, AuditBegin, R=ROW_NUMBER() OVER(partition by ID, ByID, UserAgent, OnDay order by AuditBegin desc)
	from (
		select Access.ID, AuditBegin, ByID, UserAgent, OnDay=floor(cast(Audit.ChangeDateUTC as real))
		from Access 
		join Audit on Audit.ID=AuditBegin
	) A
) C
where Access.ID=C.ID and Access.AuditBegin=C.AuditBegin and R>1

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' redundant Access records purged'

;with A as (
	select *, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
	from dbo.[Access]
)
update dbo.[Access] set AuditEnd=C.AuditBegin
from A B
left join A C on B.ID=C.ID and B.R+1=C.R
where [Access].ID=B.ID and [Access].AuditBegin=B.AuditBegin
	and isnull(B.AuditEnd,-1)<>isnull(C.AuditBegin,-1)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' Access records restitched'


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: