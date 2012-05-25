/*	
 *	Stitch back together corrupted history on custom-attribute tables.
 *	
 *	@saveChanges: must be set=1 to commit changes, otherwise everything rolls back
 */
declare @saveChanges bit; --set @saveChanges = 1

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

;with A as (
	select Definition, ID, AuditBegin, AuditEnd, Value, R=row_number() over(partition by Definition, ID order by AuditBegin)
	from dbo.CustomLongText
)
update A
set AuditEnd=B.AuditBegin
from A B
where A.Definition=B.Definition and A.ID=B.ID and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' CustomLongText records fixed'

;with A as (
	select Definition, ID, AuditBegin, AuditEnd, Value, R=row_number() over(partition by Definition, ID order by AuditBegin)
	from dbo.CustomText
)
update A
set AuditEnd=B.AuditBegin
from A B
where A.Definition=B.Definition and A.ID=B.ID and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' CustomText records fixed'

;with A as (
	select Definition, ID, AuditBegin, AuditEnd, Value, R=row_number() over(partition by Definition, ID order by AuditBegin)
	from dbo.CustomBoolean
)
update A
set AuditEnd=B.AuditBegin
from A B
where A.Definition=B.Definition and A.ID=B.ID and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' CustomBoolean records fixed'

;with A as (
	select Definition, ID, AuditBegin, AuditEnd, Value, R=row_number() over(partition by Definition, ID order by AuditBegin)
	from dbo.CustomDate
)
update A
set AuditEnd=B.AuditBegin
from A B
where A.Definition=B.Definition and A.ID=B.ID and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' CustomDate records fixed'

;with A as (
	select Definition, ID, AuditBegin, AuditEnd, Value, R=row_number() over(partition by Definition, ID order by AuditBegin)
	from dbo.CustomNumeric
)
update A
set AuditEnd=B.AuditBegin
from A B
where A.Definition=B.Definition and A.ID=B.ID and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' CustomNumeric records fixed'

;with A as (
	select Definition, PrimaryID, ForeignID, AuditBegin, AuditEnd, R=row_number() over(partition by Definition, PrimaryID, ForeignID order by AuditBegin)
	from dbo.CustomRelation
)
update A
set AuditEnd=B.AuditBegin
from A B
where A.Definition=B.Definition and A.PrimaryID=B.PrimaryID and A.ForeignID=B.ForeignID and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' CustomRelation records fixed'


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:
