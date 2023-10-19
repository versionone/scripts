/*
 *	Consolidate defect resolution field history records, on configurable time threshold (@timeThreshold) in minutes.
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @timeThreshold int;

set @timeThreshold = 5

create table #defects(ID int not null, CurrentAuditID int not null, NextAuditID int not null)
create table #suspect(ID int not null, CurrentAuditID int not null, NextAuditID int not null)
create table #bad(ID int not null, CurrentAuditID int not null, NextAuditID int not null)

set nocount on; begin tran; save tran TX

-- Defects
;with H as (
	select AA.ID, AA.AssetType, AuditID, R=ROW_NUMBER() OVER(partition by AA.ID, AA.AssetType order by AuditID)
	from dbo.AssetAudit AA
	where AA.AssetType='Defect'
)
insert #defects(ID, CurrentAuditID, NextAuditID)
select aH.ID, aH.AuditID, bH.AuditID
from H as aH
join dbo.Defect aD on aD.ID=aH.ID and aH.AuditID = aD.AuditBegin
join H as bH on bH.ID=aH.ID and bH.R=aH.R+1
join dbo.Defect bD on bD.ID=bH.ID and bH.AuditID = bD.AuditBegin

-- Consecutive Defect changes
insert #suspect(ID, CurrentAuditID, NextAuditID)
select Assets.ID, Assets.CurrentAuditID, Assets.NextAuditID
from #defects as Assets
join dbo.Defect currentD on currentD.ID=Assets.ID and currentD.AuditBegin=Assets.CurrentAuditID
join dbo.Defect nextD on nextD.ID=Assets.ID and nextD.AuditBegin=Assets.NextAuditID
join dbo.[Audit] currentA on currentA.ID = Assets.CurrentAuditID
join dbo.[Audit] nextA on nextA.ID = Assets.NextAuditID
WHERE
ISNULL(currentA.[ChangedByID] ,-1) = ISNULL(nextA.[ChangedByID],-1)  -- Consecutive changes from the same user
AND DATEDIFF(mi,currentA.[ChangeDateUTC] ,nextA.[ChangeDateUTC]) <= @timethreshold --Time threshold / period / lapse.
AND	ISNULL(currentD.[Resolution],-1) != ISNULL(nextD.[Resolution],-1) --Resolution has changed

-- Defect column comparison
declare @colsAB varchar(max)
select @colsAB=(
	select REPLACE(' and (A.{col}=C.{col} or (A.{col} is null and C.{col} is null))', '{col}', quotename(COLUMN_NAME))
	from INFORMATION_SCHEMA.COLUMNS C
	where C.TABLE_NAME='Defect' and COLUMN_NAME not in ('ID','AssetType','AuditBegin', 'Resolution', 'AuditEnd')
	for xml path('')
)

-- consecutive redundant Defect resolutions
declare @sql varchar(max); select @sql = '
insert #bad(ID, CurrentAuditID, NextAuditID)
select _.ID, CurrentAuditID, NextAuditID
from #suspect _
join dbo.Defect A on A.ID=_.ID and A.AuditBegin=_.CurrentAuditID
join dbo.Defect B on B.ID=_.ID and B.AuditBegin=_.NextAuditID
join dbo.Defect C on C.ID=_.ID and C.AuditEnd=_.CurrentAuditID AND ISNULL(C.[Resolution],-1) != ISNULL(A.[Resolution],-1)
' + @colsAB

--print @sql
exec(@sql)

-- rows to purge
select d.ID, d.AssetType, d.AuditBegin, a.ChangedByID, a.ChangeDateUTC
from #bad b
join dbo.Defect d ON d.ID=b.ID and d.AuditBegin=b.CurrentAuditID
join dbo.[Audit] a on a.ID = b.CurrentAuditID

-- purge redundant rows
delete dbo.Defect
from #bad
where Defect.ID=#bad.ID and (Defect.AuditBegin=#bad.CurrentAuditID)

declare @error int, @rowcount int

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d Defect resolution historical records consolidated', 0, 1, @rowcount) with nowait

if @rowcount=0 goto FINISHED

-- re-stitch Defect history
;with H as (
	select ID, AuditBegin, AuditEnd, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
	from dbo.Defect
)
update dbo.Defect set AuditEnd=B.AuditBegin
from H A
left join H B on A.ID=B.ID and A.R+1=B.R
where Defect.ID=A.ID and Defect.AuditBegin=A.AuditBegin
	and isnull(A.AuditEnd,-1)<>isnull(B.AuditBegin,-1)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d Defect history records restitched', 0, 1, @rowcount) with nowait


alter table dbo.Defect_Now disable trigger all

-- sync up Defect_Now with history tips from Defect
update dbo.Defect_Now set AuditBegin=Defect.AuditBegin
from dbo.Defect
where Defect.ID=Defect_Now.ID and Defect.AuditEnd is null and Defect.AuditBegin<>Defect_Now.AuditBegin

select @rowcount=@@ROWCOUNT, @error=@@ERROR
alter table dbo.Defect_Now enable trigger all
if @error<>0 goto ERR
raiserror('%d Defect_Now records syncd', 0, 1, @rowcount) with nowait

if @saveChanges=1 begin
	DBCC DBREINDEX([Defect])

	if OBJECT_ID('dbo.AssetAudit_Rebuild', 'P') is not null
	begin
		exec dbo.AssetAudit_Rebuild
		DBCC DBREINDEX([AssetAudit])
	end
	if OBJECT_ID('dbo.Asset_Rebuild', 'P') is not null
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
drop table #defects
