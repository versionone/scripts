/*
 *	Consolidate description field history records, on configurable time threshold (@timeThreshold) in minutes.
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @timeThreshold int;

set @timeThreshold = 5

create table #baseassets(ID int not null, CurrentAuditID int not null, NextAuditID int not null)
create table #suspect(ID int not null, CurrentAuditID int not null, NextAuditID int not null)
create table #bad(ID int not null, CurrentAuditID int not null, NextAuditID int not null)

set nocount on; begin tran; save tran TX

-- BaseAssets
;with H as (
	select AA.ID, AA.AssetType, AuditID, R=ROW_NUMBER() OVER(partition by AA.ID, AA.AssetType order by AuditID)
	from dbo.AssetAudit AA
)
insert #baseassets(ID, CurrentAuditID, NextAuditID)
select aH.ID, aH.AuditID, bH.AuditID
from H as aH
join dbo.BaseAsset aBA on aBA.ID=aH.ID and aBA.AssetType=aH.AssetType and aH.AuditID = aBA.AuditBegin
join H as bH on bH.ID=aH.ID and aH.AssetType=bH.AssetType and bH.R=aH.R+1
join dbo.BaseAsset bBA on bBA.ID=bH.ID and bBA.AssetType=bH.AssetType and bH.AuditID = bBA.AuditBegin

-- Consecutive BaseAsset changes
insert #suspect(ID, CurrentAuditID, NextAuditID)
select Assets.ID, Assets.CurrentAuditID, Assets.NextAuditID
from #baseassets as Assets
join dbo.BaseAsset currentBA on currentBA.ID=Assets.ID and currentBA.AuditBegin=Assets.CurrentAuditID
join dbo.BaseAsset nextBA on nextBA.ID=Assets.ID and nextBA.AuditBegin=Assets.NextAuditID
join dbo.[Audit] currentA on currentA.ID = Assets.CurrentAuditID
join dbo.[Audit] nextA on nextA.ID = Assets.NextAuditID
WHERE
ISNULL(currentA.[ChangedByID] ,-1) = ISNULL(nextA.[ChangedByID],-1)  -- Consecutive changes from the same user
AND DATEDIFF(mi,currentA.[ChangeDateUTC] ,nextA.[ChangeDateUTC]) <= @timethreshold --Time threshold / period / lapse.
AND	ISNULL(currentBA.[Description],-1) != ISNULL(nextBA.[Description],-1) --Description has changed

-- BaseAsset column comparison
declare @colsAB varchar(max)
select @colsAB=(
	select REPLACE(' and (A.{col}=C.{col} or (A.{col} is null and C.{col} is null))', '{col}', quotename(COLUMN_NAME))
	from INFORMATION_SCHEMA.COLUMNS C
	where C.TABLE_NAME='BaseAsset' and COLUMN_NAME not in ('ID','AssetType','AuditBegin', 'Description', 'AuditEnd')
	for xml path('')
)

-- consecutive redundant BaseAsset descriptions
declare @sql varchar(max); select @sql = '
insert #bad(ID, CurrentAuditID, NextAuditID)
select _.ID, CurrentAuditID, NextAuditID
from #suspect _
join dbo.BaseAsset A on A.ID=_.ID and A.AuditBegin=_.CurrentAuditID
join dbo.BaseAsset B on B.ID=_.ID and B.AuditBegin=_.NextAuditID
join dbo.BaseAsset C on C.ID=_.ID and C.AuditEnd=_.CurrentAuditID AND ISNULL(C.[Description],-1) != ISNULL(A.[Description],-1)
' + @colsAB

--print @sql
exec(@sql)

-- rows to purge
select ba.ID, ba.AssetType, ba.AuditBegin, a.ChangedByID, a.ChangeDateUTC
from #bad b
join dbo.BaseAsset ba ON ba.ID=b.ID and ba.AuditBegin=b.CurrentAuditID
join dbo.[Audit] a on a.ID = b.CurrentAuditID

-- purge redundant rows
delete dbo.BaseAsset
from #bad
where BaseAsset.ID=#bad.ID and (BaseAsset.AuditBegin=#bad.CurrentAuditID)

declare @error int, @rowcount int

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d BaseAsset description historical records consolidated', 0, 1, @rowcount) with nowait

if @rowcount=0 goto FINISHED

-- re-stitch BaseAsset history
;with H as (
	select ID, AuditBegin, AuditEnd, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
	from dbo.BaseAsset
)
update dbo.BaseAsset set AuditEnd=B.AuditBegin
from H A
left join H B on A.ID=B.ID and A.R+1=B.R
where BaseAsset.ID=A.ID and BaseAsset.AuditBegin=A.AuditBegin
	and isnull(A.AuditEnd,-1)<>isnull(B.AuditBegin,-1)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d BaseAsset history records restitched', 0, 1, @rowcount) with nowait


alter table dbo.BaseAsset_Now disable trigger all

-- sync up BaseAsset_Now with history tips from BaseAsset
update dbo.BaseAsset_Now set AuditBegin=BaseAsset.AuditBegin
from dbo.BaseAsset
where BaseAsset.ID=BaseAsset_Now.ID and BaseAsset.AuditEnd is null and BaseAsset.AuditBegin<>BaseAsset_Now.AuditBegin

select @rowcount=@@ROWCOUNT, @error=@@ERROR
alter table dbo.BaseAsset_Now enable trigger all
if @error<>0 goto ERR
raiserror('%d BaseAsset_Now records syncd', 0, 1, @rowcount) with nowait

if @saveChanges=1 begin
	DBCC DBREINDEX([BaseAsset])

	if OBJECT_ID('dbo.AssetAudit', 'U') is not null
	begin
		exec dbo.AssetAudit_Rebuild
		DBCC DBREINDEX([AssetAudit])
	end
	if OBJECT_ID('dbo.Asset', 'U') is not null
	begin
		exec dbo.Asset_Rebuild
		DBCC DBREINDEX([Asset])
		DBCC DBREINDEX([Asset_Now])
	end
end

FINISHED:
if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:

drop table #bad
drop table #suspect
drop table #baseassets
