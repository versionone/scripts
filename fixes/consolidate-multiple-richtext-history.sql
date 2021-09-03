/*
 *	Consolidate field history records, on configurable time threshold (@timeThreshold) in minutes.
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @TableNameWithoutSchema varchar(100); --set @TableNameWithoutSchema = 'Test'; --Table Name Ex: Test, RegressionTest, BaseAsset
declare @TableName varchar(100); set @TableName = quotename(@TableNameWithoutSchema);
declare @TableName_Now varchar(100); set @TableName_Now = quotename(@TableNameWithoutSchema + '_Now');
declare @FieldName varchar(100); --set @FieldName = 'ExpectedResults'; -- Table attribute Ex: Description, ExpectedResults, Setup
declare @Field varchar(100); set @Field = quotename(@FieldName);
declare @timeThreshold int;

set @timeThreshold = 5

create table #assets(ID int not null, CurrentAuditID int not null, NextAuditID int not null)
create table #suspect(ID int not null, CurrentAuditID int not null, NextAuditID int not null)
create table #bad(ID int not null, CurrentAuditID int not null, NextAuditID int not null)

set nocount on; begin tran; save tran TX

-- Asset Rows
declare @q1 varchar(max);
select @q1 = ';
with H as (
	select AA.ID, AA.AssetType, AuditID, R=ROW_NUMBER() OVER(partition by AA.ID, AA.AssetType order by AuditID)
	from dbo.AssetAudit AA
)
insert #assets(ID, CurrentAuditID, NextAuditID)
select aH.ID, aH.AuditID, bH.AuditID
from H as aH
join dbo.' + @TableName + ' aAsset on aAsset.ID=aH.ID and aAsset.AssetType=aH.AssetType and aH.AuditID = aAsset.AuditBegin
join H as bH on bH.ID=aH.ID and aH.AssetType=bH.AssetType and bH.R=aH.R+1
join dbo.' + @TableName + ' bAsset on bAsset.ID=bH.ID and bAsset.AssetType=bH.AssetType and bH.AuditID = bAsset.AuditBegin'

-- Consecutive Asset changes
declare @q2 varchar(max);
select @q2 = ';
insert #suspect(ID, CurrentAuditID, NextAuditID)
select Assets.ID, Assets.CurrentAuditID, Assets.NextAuditID
from #assets as Assets
join dbo.' + @TableName + ' currentAsset on currentAsset.ID=Assets.ID and currentAsset.AuditBegin=Assets.CurrentAuditID
join dbo.' + @TableName + ' nextAsset on nextAsset.ID=Assets.ID and nextAsset.AuditBegin=Assets.NextAuditID
join dbo.Audit currentA on currentA.ID = Assets.CurrentAuditID
join dbo.Audit nextA on nextA.ID = Assets.NextAuditID
WHERE
ISNULL(currentA.ChangedByID,-1) = ISNULL(nextA.ChangedByID,-1)  -- Consecutive changes from the same user
AND DATEDIFF(mi,currentA.ChangeDateUTC,nextA.ChangeDateUTC) <= ' + CAST(@timethreshold as varchar(10)) + ' --Time threshold / period / lapse.
AND	ISNULL(currentAsset.' + @Field + ',-1) != ISNULL(nextAsset.' + @Field + ',-1) --@FieldName has changed '

-- Asset column comparison
declare @colsAB varchar(max)
select @colsAB=(
	select REPLACE(' and (A.{col}=C.{col} or (A.{col} is null and C.{col} is null))', '{col}', quotename(COLUMN_NAME))
	from INFORMATION_SCHEMA.COLUMNS C
	where C.TABLE_NAME=@TableNameWithoutSchema and COLUMN_NAME not in ('ID','AssetType','AuditBegin', @FieldName, 'AuditEnd')
	for xml path('')
)

-- consecutive redundant entries
declare @q3 varchar(max); 
select @q3 = '
insert #bad(ID, CurrentAuditID, NextAuditID)
select _.ID, CurrentAuditID, NextAuditID
from #suspect _
join dbo.' + @TableName + ' A on A.ID=_.ID and A.AuditBegin=_.CurrentAuditID
join dbo.' + @TableName + ' B on B.ID=_.ID and B.AuditBegin=_.NextAuditID
join dbo.' + @TableName + ' C on C.ID=_.ID and C.AuditEnd=_.CurrentAuditID AND ISNULL(C.' + @Field + ',-1) != ISNULL(A.' + @Field + ',-1)
' + @colsAB

-- rows to purge
declare @q4 varchar(max);
select @q4 = ';
select cAsset.ID, cAsset.AssetType, cAsset.AuditBegin, a.ChangedByID, a.ChangeDateUTC
from #bad b
join dbo.' + @TableName + ' cAsset ON cAsset.ID=b.ID and cAsset.AuditBegin=b.CurrentAuditID
join dbo.Audit a on a.ID = b.CurrentAuditID'

-- purge redundant rows
declare @q5 varchar(max);
select @q5 = ';
delete dbo.' + @TableName + '
from #bad
where ' + @TableName + '.ID=#bad.ID and ' + @TableName + '.AuditBegin=#bad.CurrentAuditID'

declare @error int, @rowcount int

exec(@q1 + @q2 + @q3 + @q4 + @q5)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d %s.%s historical records consolidated', 0, 1, @rowcount, @TableNameWithoutSchema, @FieldName) with nowait

if @rowcount=0 goto FINISHED

-- re-stitch Asset history
declare @q6 varchar(max)
select @q6 = ';
with H as (
	select ID, AuditBegin, AuditEnd, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
	from dbo.' + @TableName + '
)
update dbo.' + @TableName + ' set AuditEnd=B.AuditBegin
from H A
left join H B on A.ID=B.ID and A.R+1=B.R
where ' + @TableName + '.ID=A.ID and ' + @TableName + '.AuditBegin=A.AuditBegin
	and isnull(A.AuditEnd,-1)<>isnull(B.AuditBegin,-1)'
exec(@q6)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d %s history records restitched', 0, 1, @rowcount, @TableNameWithoutSchema) with nowait

declare @q7 varchar(max)
select @q7 = ';
alter table dbo.' + @TableName_Now + ' disable trigger all'
exec(@q7)

-- sync up Table_Now with history tips from Table
declare @q8 varchar(max)
select @q8 = ';
update dbo.' + @TableName_Now + ' set AuditBegin=' + @TableName + '.AuditBegin
from dbo.' + @TableName + '
where ' + @TableName + '.ID=' + @TableName_Now + '.ID and ' + @TableName + '.AuditEnd is null and ' + @TableName + '.AuditBegin<>' + @TableName_Now + '.AuditBegin'
exec(@q8)

select @rowcount=@@ROWCOUNT, @error=@@ERROR

declare @q9 varchar(max)
select @q9 = ';
alter table dbo.' + @TableName_Now + ' enable trigger all'
exec(@q9)

if @error<>0 goto ERR
raiserror('%d records syncd', 0, 1, @rowcount) with nowait

if @saveChanges = 1 begin
	declare @q10 varchar(max);
	set @q10 = ';
	DBCC DBREINDEX(' + @TableName + ')
	exec dbo.AssetAudit_Rebuild
	DBCC DBREINDEX(AssetAudit)
	'
	exec(@q10)
end

FINISHED:
if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:

drop table #bad
drop table #suspect
drop table #assets