/*
 *	Consolidate description field history records, on configurable time threshold (@timeThreshold) in minutes.
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @timeThreshold int;

set @timeThreshold = 5

create table #suspect(ID int not null, PreviousAuditID int null, CurrentAuditID int null, NextAuditId int null)
create table #bad(ID int not null, PreviousAuditID int null, CurrentAuditID int null, NextAuditId int null)

set nocount on; begin tran; save tran TX

-- consecutive BaseAsset changes
;with H as (
	select AA.ID, AssetType, AuditID, A.[ChangedByID], A.ChangeDateUTC ,R=ROW_NUMBER() OVER(partition by AA.ID, AssetType order by AuditID)
	from dbo.AssetAudit AA
	join [Audit] A ON A.ID = AA.AuditID
)

insert #suspect(ID,  PreviousAuditID, CurrentAuditID, NextAuditID)
select A.ID,
C.AuditID PreviousAuditID,
A.AuditID CurrentAuditID,
B.AuditID NextAuditID
from H A
join dbo.BaseAsset bA on bA.ID=A.ID and bA.AssetType=A.AssetType and bA.AuditBegin=A.AuditID

join H B on B.ID=A.ID and B.AssetType=A.AssetType and B.R=A.R+1
join dbo.BaseAsset bB on bB.ID=B.ID and bB.AssetType=B.AssetType and bB.AuditBegin=B.AuditID

left join H C on C.ID=B.ID and C.AssetType=B.AssetType and C.R=A.R-1
left join dbo.BaseAsset bC on bC.ID=C.ID and bC.AssetType=C.AssetType and bC.AuditBegin=C.AuditID

WHERE 1=1
AND ISNULL(B.[ChangedByID] ,-1) = A.[ChangedByID]  -- Consecutive changes from the same user
AND DATEDIFF(mi,A.[ChangeDateUTC] ,B.[ChangeDateUTC]) < @timethreshold --Time threshold / period / lapse.
AND
(
	ISNULL(bC.[Description],-1) != ISNULL(bA.[Description],-1) --Description has changed
	AND
	ISNULL(bB.[Description],-1) != ISNULL(bA.[Description],-1) --Description has changed
)

-- BaseAsset column comparison
declare @colsAB varchar(max), @colsBC varchar(max)
select @colsAB=(
	select REPLACE(' and (A.{col}=B.{col} or (A.{col} is null and B.{col} is null))', '{col}', quotename(COLUMN_NAME))
	from INFORMATION_SCHEMA.COLUMNS C
	where C.TABLE_NAME='BaseAsset' and COLUMN_NAME not in ('ID','AssetType','AuditBegin', 'Description', 'AuditEnd')
	for xml path('')
)
select @colsBC=(
	select REPLACE(' and (B.{col}=C.{col} or (B.{col} is null and C.{col} is null))', '{col}', quotename(COLUMN_NAME))
	from INFORMATION_SCHEMA.COLUMNS C
	where C.TABLE_NAME='BaseAsset' and COLUMN_NAME not in ('ID','AssetType','AuditBegin', 'Description', 'AuditEnd')
	for xml path('')
)

-- consecutive redundant BaseAsset re-open/close
declare @sql varchar(max); select @sql = '
insert #bad(ID, PreviousAuditID, CurrentAuditID, NextAuditID)
select _.ID, PreviousAuditID, CurrentAuditID, NextAuditID
from #suspect _
join dbo.BaseAsset A on A.ID=_.ID and A.AuditBegin=_.PreviousAuditID
join dbo.BaseAsset B on B.ID=_.ID and B.AuditBegin=_.CurrentAuditID
' + @colsAB + '
join dbo.BaseAsset C on C.ID=_.ID and C.AuditBegin=_.NextAuditID
' + @colsBC

-- print @sql
exec(@sql)

-- purge redundant rows
delete dbo.BaseAsset
from #bad
where BaseAsset.ID=#bad.ID and (BaseAsset.AuditBegin=#bad.CurrentAuditID)

declare @error int, @rowcount varchar(20)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' BaseAsset description historical records consolidated'

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
print @rowcount + ' BaseAsset history records restitched'

alter table dbo.BaseAsset_Now disable trigger all

-- sync up BaseAsset_Now with history tips from BaseAsset
update dbo.BaseAsset_Now set AuditBegin=BaseAsset.AuditBegin, ClosedAuditID=BaseAsset.ClosedAuditID
from dbo.BaseAsset
where BaseAsset.ID=BaseAsset_Now.ID and BaseAsset.AuditEnd is null and BaseAsset.AuditBegin<>BaseAsset_Now.AuditBegin

select @rowcount=@@ROWCOUNT, @error=@@ERROR
alter table dbo.BaseAsset_Now enable trigger all
if @error<>0 goto ERR
print @rowcount + ' BaseAsset_Now records syncd'

if @saveChanges=1 begin
	DBCC DBREINDEX([BaseAsset])

	exec dbo.AssetAudit_Rebuild
	DBCC DBREINDEX([AssetAudit])
end

FINISHED:
if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:

drop table #bad
drop table #suspect
