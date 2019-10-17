/*
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */

declare @saveChanges bit; --set @saveChanges = 1

set nocount on

create table #inuse (ID int not null primary key)

declare @sql varchar(8000); select @sql='insert #inuse(ID)'
select @sql = @sql + ' select ' + QUOTENAME(d.Name) + ' from dbo.' + QUOTENAME(t.Name) + ' union' 
from AttributeDefinition_Now d
join AssetType_Now t on t.ID=d.AssetID
where d.AttributeType='Blob'
select @sql = left(@sql, len(@sql) - len(' union'))

--print @sql
exec (@sql)

select count(*) InUse from #inuse
select count(*) Before from dbo.Blob

declare @error int, @rowcount int
begin tran; save tran TX

delete Blob
from dbo.Blob
left join #inuse on #inuse.ID=Blob.ID
where Blob.Hash is null and #inuse.ID is null

--select Blob.ID, Hash from dbo.Blob left join #inuse on #inuse.ID=Blob.ID where #inuse.ID is null

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d unused Blobs dropped', 0, 1, @rowcount) with nowait

if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)

ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE:

select count(*) After from dbo.Blob

drop table #inuse
