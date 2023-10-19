/*	
 *	Consolidate consecutive close/re-open historical List records.
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; -- set @saveChanges = 1

create table #listassets(ID int not null, AuditID1 int not null, AuditID2 int not null, AuditID3 int not null)
create table #suspect(ID int not null, AuditID1 int not null, AuditID2 int not null, AuditID3 int not null)
create table #bad(ID int not null, AuditID1 int not null, AuditID2 int not null, AuditID3 int not null)

set nocount on; begin tran; save tran TX

-- consecutive List changes
;with H as (
	select ID, AssetType, AuditID, R=ROW_NUMBER() OVER(partition by ID, AssetType order by AuditID)
	from dbo.AssetAudit a
)
insert #listassets(ID, AuditID1, AuditID2, AuditID3)
select A.ID, A.AuditID AuditID1, B.AuditID AuditID2, C.AuditID AuditID3
from H A
join dbo.List bA on bA.ID=A.ID and bA.AssetType=A.AssetType and bA.AuditBegin=A.AuditID
join H B on B.ID=A.ID and B.AssetType=A.AssetType and B.R=A.R+1
join dbo.List bB on bB.ID=B.ID and bB.AssetType=B.AssetType and bB.AuditBegin=B.AuditID
join H C on C.ID=B.ID and C.AssetType=B.AssetType and C.R=B.R+1
join dbo.List bC on bC.ID=C.ID and bC.AssetType=C.AssetType and bC.AuditBegin=C.AuditID

-- consecutive List re-open/close
insert #suspect(ID, AuditID1, AuditID2, AuditID3)
select _.ID, AuditID1, AuditID2, AuditID3 from #listassets _
join dbo.List A on A.ID=_.ID and A.AuditBegin=_.AuditID1 and A.AssetState=64
join dbo.List B on B.ID=_.ID and B.AuditBegin=_.AuditID2 and B.AssetState=128
join dbo.List C on C.ID=_.ID and C.AuditBegin=_.AuditID3 and C.AssetState=64

-- List column comparison
declare @colsAB varchar(max), @colsBC varchar(max)
select @colsAB=(
	select REPLACE(' and (A.{col}=B.{col} or (A.{col} is null and B.{col} is null))', '{col}', quotename(COLUMN_NAME))
	from INFORMATION_SCHEMA.COLUMNS C 
	where C.TABLE_NAME='List_Now' and COLUMN_NAME not in ('ID','AssetType','AuditBegin', 'AssetState')
	for xml path('')
)
select @colsBC=(
	select REPLACE(' and (B.{col}=C.{col} or (B.{col} is null and C.{col} is null))', '{col}', quotename(COLUMN_NAME))
	from INFORMATION_SCHEMA.COLUMNS C 
	where C.TABLE_NAME='List_Now' and COLUMN_NAME not in ('ID','AssetType','AuditBegin', 'AssetState')
	for xml path('')
)

-- consecutive redundant List re-open/close
declare @sql varchar(max); select @sql = '
insert #bad(ID, AuditID1, AuditID2, AuditID3)
select _.ID, AuditID1, AuditID2, AuditID3 from #suspect _
join dbo.List A on A.ID=_.ID and A.AuditBegin=_.AuditID1
join dbo.List B on B.ID=_.ID and B.AuditBegin=_.AuditID2
' + @colsAB + '
join dbo.List C on C.ID=_.ID and C.AuditBegin=_.AuditID3
' + @colsBC

-- print @sql
exec(@sql)

declare @error int, @rowcount varchar(20)

-- purge redundant rows
delete dbo.List
from #bad
where List.ID=#bad.ID and (List.AuditBegin=#bad.AuditID2 or List.AuditBegin=#bad.AuditID3)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' List re-open/close historical records consolidated'

if @rowcount=0 goto FINISHED

-- re-stitch List history
;with H as (
	select ID, AuditBegin, AuditEnd, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
	from dbo.List
)
update dbo.List set AuditEnd=B.AuditBegin
from H A
left join H B on A.ID=B.ID and A.R+1=B.R
where List.ID=A.ID and List.AuditBegin=A.AuditBegin
	and isnull(A.AuditEnd,-1)<>isnull(B.AuditBegin,-1)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' List history records restitched'

alter table dbo.List_Now disable trigger all

-- sync up List_Now with history tips from List
update dbo.List_Now set AuditBegin=List.AuditBegin 
from dbo.List
where List.ID=List_Now.ID and List.AuditEnd is null and List.AuditBegin<>List_Now.AuditBegin

select @rowcount=@@ROWCOUNT, @error=@@ERROR
alter table dbo.List_Now enable trigger all
if @error<>0 goto ERR
print @rowcount + ' List_Now records syncd'

if @saveChanges=1 begin
	DBCC DBREINDEX([List])

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
drop table #listassets
