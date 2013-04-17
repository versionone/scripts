/*	
 *	Consolidate consecutive re-open/close historical BaseAsset records.
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; -- set @saveChanges = 1

set nocount on; begin tran; save tran TX

-- consecutive BaseAsset changes
create table #baseassets(ID int not null, AuditID1 int not null, AuditID2 int not null, AuditID3 int not null)
;with H as (
	select ID, AssetType, AuditID, R=ROW_NUMBER() OVER(partition by ID, AssetType order by AuditID)
	from dbo.AssetAudit a
)
insert #baseassets(ID, AuditID1, AuditID2, AuditID3)
select A.ID, A.AuditID AuditID1, B.AuditID AuditID2, C.AuditID AuditID3
from H A
join dbo.BaseAsset bA on bA.ID=A.ID and bA.AssetType=A.AssetType and bA.AuditBegin=A.AuditID
join H B on B.ID=A.ID and B.AssetType=A.AssetType and B.R=A.R+1
join dbo.BaseAsset bB on bB.ID=B.ID and bB.AssetType=B.AssetType and bB.AuditBegin=B.AuditID
join H C on C.ID=B.ID and C.AssetType=B.AssetType and C.R=B.R+1
join dbo.BaseAsset bC on bC.ID=C.ID and bC.AssetType=C.AssetType and bC.AuditBegin=C.AuditID

-- consecutive BaseAsset re-open/close
create table #suspect(ID int not null, AuditID1 int not null, AuditID2 int not null, AuditID3 int not null)
insert #suspect(ID, AuditID1, AuditID2, AuditID3)
select _.ID, AuditID1, AuditID2, AuditID3 from #baseassets _
join dbo.BaseAsset A on A.ID=_.ID and A.AuditBegin=_.AuditID1 and A.AssetState=128
join dbo.BaseAsset B on B.ID=_.ID and B.AuditBegin=_.AuditID2 and B.AssetState=64
join dbo.BaseAsset C on C.ID=_.ID and C.AuditBegin=_.AuditID3 and C.AssetState=128

-- BaseAsset column comparison
declare @colsAB varchar(max), @colsBC varchar(max)
select @colsAB=(
	select REPLACE(' and (A.{col}=B.{col} or (A.{col} is null and B.{col} is null))', '{col}', quotename(COLUMN_NAME))
	from INFORMATION_SCHEMA.COLUMNS C 
	where C.TABLE_NAME='BaseAsset_Now' and COLUMN_NAME not in ('ID','AssetType','AuditBegin', 'AssetState')
	for xml path('')
)
select @colsBC=(
	select REPLACE(' and (B.{col}=C.{col} or (B.{col} is null and C.{col} is null))', '{col}', quotename(COLUMN_NAME))
	from INFORMATION_SCHEMA.COLUMNS C 
	where C.TABLE_NAME='BaseAsset_Now' and COLUMN_NAME not in ('ID','AssetType','AuditBegin', 'AssetState')
	for xml path('')
)

-- consecutive redundant BaseAsset re-open/close
declare @sql varchar(max); select @sql = '
insert #bad(ID, AuditID1, AuditID2, AuditID3)
select _.ID, AuditID1, AuditID2, AuditID3 from #suspect _
join dbo.BaseAsset A on A.ID=_.ID and A.AuditBegin=_.AuditID1
join dbo.BaseAsset B on B.ID=_.ID and B.AuditBegin=_.AuditID2
' + @colsAB + '
join dbo.BaseAsset C on C.ID=_.ID and C.AuditBegin=_.AuditID3
' + @colsBC

create table #bad(ID int not null, AuditID1 int not null, AuditID2 int not null, AuditID3 int not null)
-- print @sql
exec(@sql)

declare @error int, @rowcount int

-- purge redundant rows
delete dbo.BaseAsset
from #bad
where BaseAsset.ID=#bad.ID and (BaseAsset.AuditBegin=#bad.AuditID2 or BaseAsset.AuditBegin=#bad.AuditID3)

select @rowcount=@@ROWCOUNT, @error=@@ERROR

if @error=0 and @rowcount>0 begin
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
				
	alter table dbo.BaseAsset_Now disable trigger all

	-- sync up BaseAsset_Now with history tips from BaseAsset
	update dbo.BaseAsset_Now set AuditBegin=BaseAsset.AuditBegin 
	from dbo.BaseAsset
	where BaseAsset.ID=BaseAsset_Now.ID and BaseAsset.AuditEnd is null and BaseAsset.AuditBegin<>BaseAsset_Now.AuditBegin

	alter table dbo.BaseAsset_Now enable trigger all
end

drop table #bad
drop table #suspect
drop table #baseassets

if @error<>0 goto ERR
if @rowcount>0 begin
	print cast(@rowcount as varchar(20)) + ' BaseAsset re-open/close historical records consolidated'

	if @saveChanges=1 begin
		DBCC DBREINDEX([BaseAsset])

		exec dbo.AssetAudit_Rebuild
		DBCC DBREINDEX([AssetAudit])
	end
end

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: