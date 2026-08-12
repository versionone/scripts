/*	
 *	Stitch back together corrupted history on BaseAssetTaggedWith and CustomTag tables.
 *	
 *	@saveChanges: must be set=1 to commit changes, otherwise everything rolls back
 */
declare @saveChanges bit; --set @saveChanges = 1

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

;with A as (
	select ID, AuditBegin, AuditEnd, Value, R=row_number() over(partition by ID, Value order by AuditBegin)
	from dbo.BaseAssetTaggedWith
)
update A
set AuditEnd=B.AuditBegin
from A B
where A.ID=B.ID and A.Value=B.Value and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' BaseAssetTaggedWith records fixed'

if exists (select * from INFORMATION_SCHEMA.TABLES where TABLE_NAME='CustomTag') begin
    ;with A as (
        select Definition, ID, AuditBegin, AuditEnd, Value, R=row_number() over(partition by Definition, ID, Value order by AuditBegin)
        from dbo.CustomTag
    )
    update A
    set AuditEnd=B.AuditBegin
    from A B
    where A.Definition=B.Definition and A.ID=B.ID and A.Value=B.Value and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

    select @rowcount=@@ROWCOUNT, @error=@@ERROR
    if @error<>0 goto ERR
    print @rowcount + ' CustomTag records fixed'
end

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit