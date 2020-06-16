/*	
 *	Ensure ClosedAuditID always reflects AuditBegin of most recent closure
 *	(Active => Closed transition) throughout entire BaseAsset history.
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1

BEGIN
	if not exists (select * from INFORMATION_SCHEMA.TABLES where TABLE_NAME='BaseAsset') begin
		raiserror('No such table [BaseAsset]',16,1)
		goto DONE
	end
END

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

alter table dbo.BaseAsset_Now disable trigger all
if @@ERROR<>0 goto ERR

update dbo.BaseAsset set ClosedAuditID=null where ClosedAuditID is not null and AssetState<128
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' open BaseAsset records cleared'

update dbo.BaseAsset
set ClosedAuditID=bac.AuditBegin
from dbo.BaseAsset ba
cross apply (select top 1 bac.* from BaseAsset bac where bac.ID=ba.ID and bac.AssetState=128 and bac.AuditBegin<=ba.AuditBegin and not exists (select * from BaseAsset bao where bao.ID=bac.ID and (bao.AssetState<128 or (bao.AssetState>=192 and bao.AssetState<255)) and bao.AuditBegin>bac.AuditBegin and bao.AuditBegin<ba.AuditBegin) order by AuditBegin) bac
where ba.AssetState>=128 and (ba.AssetState<192 or ba.AssetState=255) and (ba.ClosedAuditID is null or ba.ClosedAuditID<>bac.AuditBegin)
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' closed BaseAsset records updated'

update dbo.BaseAsset_Now
set ClosedAuditID=ba.ClosedAuditID
from dbo.BaseAsset ba
where ba.ID=BaseAsset_Now.ID and ba.AuditEnd is null
 and ((ba.ClosedAuditID is null and BaseAsset_Now.ClosedAuditID is not null) or (ba.ClosedAuditID is not null and BaseAsset_Now.ClosedAuditID is null) or ba.ClosedAuditID<>BaseAsset_Now.ClosedAuditID)
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' BaseAsset_Now records synced'

alter table dbo.BaseAsset_Now enable trigger all
if @@ERROR<>0 goto ERR

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit

if (@saveChanges = 1) DBCC DBREINDEX([BaseAsset])
if (@saveChanges = 1) DBCC DBREINDEX([BaseAsset_Now])

DONE: