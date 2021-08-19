/*
 *	Consolidate field history records, on configurable time threshold (@timeThreshold) in minutes.
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @TableNameWithoutSchema varchar(100); --set @TableNameWithoutSchema = 'Test'; --Table Name Ex: Test, RegressionTest, BaseAsset
declare @TableName varchar(100); --set @TableName = 'dbo.'+ @TableNameWithoutSchema;
declare @TableName_Now varchar(100); --set @TableName_Now = @TableName+'_Now';
declare @FieldName varchar(100); --set @FieldName = 'ExpectedResults'; -- Table attribute Ex: Description, ExpectedResults, Setup
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
join '+ @TableName +' aAsset on aAsset.ID=aH.ID and aAsset.AssetType=aH.AssetType and aH.AuditID = aAsset.AuditBegin
join H as bH on bH.ID=aH.ID and aH.AssetType=bH.AssetType and bH.R=aH.R+1
join '+ @TableName +' bAsset on bAsset.ID=bH.ID and bAsset.AssetType=bH.AssetType and bH.AuditID = bAsset.AuditBegin'

-- Consecutive Asset changes
declare @q2 varchar(max);
select @q2 = ';
insert #suspect(ID, CurrentAuditID, NextAuditID)
select Assets.ID, Assets.CurrentAuditID, Assets.NextAuditID
from #assets as Assets
join '+ @TableName +' currentAsset on currentAsset.ID=Assets.ID and currentAsset.AuditBegin=Assets.CurrentAuditID
join '+ @TableName +' nextAsset on nextAsset.ID=Assets.ID and nextAsset.AuditBegin=Assets.NextAuditID
join dbo.[Audit] currentA on currentA.ID = Assets.CurrentAuditID
join dbo.[Audit] nextA on nextA.ID = Assets.NextAuditID
WHERE
ISNULL(currentA.[ChangedByID] ,-1) = ISNULL(nextA.[ChangedByID],-1)  -- Consecutive changes from the same user
AND DATEDIFF(mi,currentA.[ChangeDateUTC] ,nextA.[ChangeDateUTC]) <= ' + CAST(@timethreshold as varchar(10)) + ' --Time threshold / period / lapse.
AND	ISNULL(currentAsset.[' + @FieldName + '],-1) != ISNULL(nextAsset.[' + @FieldName + '],-1) --@FieldName has changed '

-- Asset column comparison
declare @colsAB varchar(max)
select @colsAB=(
	select REPLACE(' and (A.{col}=C.{col} or (A.{col} is null and C.{col} is null))', '{col}', quotename(COLUMN_NAME))
	from INFORMATION_SCHEMA.COLUMNS C
	where C.TABLE_NAME= @TableNameWithoutSchema and COLUMN_NAME not in ('ID','AssetType','AuditBegin', @FieldName, 'AuditEnd')
	for xml path('')
)

-- consecutive redundant entries
declare @q3 varchar(max); 
select @q3 = '
insert #bad(ID, CurrentAuditID, NextAuditID)
select _.ID, CurrentAuditID, NextAuditID
from #suspect _
join ' + @TableName + ' A on A.ID=_.ID and A.AuditBegin=_.CurrentAuditID
join ' + @TableName + ' B on B.ID=_.ID and B.AuditBegin=_.NextAuditID
join ' + @TableName + ' C on C.ID=_.ID and C.AuditEnd=_.CurrentAuditID AND ISNULL(C.[' + @FieldName + '],-1) != ISNULL(A.[' + @FieldName + '],-1)
' + @colsAB

-- rows to purge
declare @q4 varchar(max);
select @q4 = ';
select cAsset.ID, cAsset.AssetType, cAsset.AuditBegin, a.ChangedByID, a.ChangeDateUTC
from #bad b
join '+ @TableName +' cAsset ON cAsset.ID=b.ID and cAsset.AuditBegin=b.CurrentAuditID
join dbo.[Audit] a on a.ID = b.CurrentAuditID'

-- purge redundant rows
declare @q5 varchar(max);
select @q5 = ';
delete '+ @TableName +'
from #bad
where '+ @TableName + '.ID=#bad.ID and ('+ @TableName +'.AuditBegin=#bad.CurrentAuditID)'

declare @error int, @rowcount int

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d %s %s historical records consolidated', 0, 1, @rowcount, @TableName, @FieldName) with nowait

if @rowcount=0 goto FINISHED

-- re-stitch Asset history
declare @q6 varchar(max)
select @q6 = ';
with H as (
	select ID, AuditBegin, AuditEnd, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
	from ' + @TableName + '
)
update ' + @TableName + ' set AuditEnd=B.AuditBegin
from H A
left join H B on A.ID=B.ID and A.R+1=B.R
where ' + @TableName + '.ID=A.ID and ' + @TableName + '.AuditBegin=A.AuditBegin
	and isnull(A.AuditEnd,-1)<>isnull(B.AuditBegin,-1)'

exec(@q1 + @q2 + @q3 + @q4 + @q5 + @q6)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d %s history records restitched', 0, 1, @rowcount, @TableName) with nowait

declare @q7 varchar(max)
select @q7 = ';
alter table ' + @TableName_Now + ' disable trigger all'

exec(@q7)

-- sync up Table_Now with history tips from Table
declare @q8 varchar(max)
select @q8 = ';
update ' + @TableName_Now + ' set AuditBegin=' + @TableName + '.AuditBegin
from ' + @TableName + '
where ' + @TableName + '.ID=' + @TableName_Now + '.ID and ' + @TableName + '.AuditEnd is null and ' + @TableName + '.AuditBegin<>' + @TableName_Now + '.AuditBegin'

exec(@q8)

select @rowcount=@@ROWCOUNT, @error=@@ERROR

declare @q9 varchar(max)
select @q9 = ';
alter table ' + @TableName_Now + ' enable trigger all'
exec(@q9)

if @error<>0 goto ERR
raiserror('%d records syncd', 0, 1, @rowcount) with nowait

declare @q10 varchar(max);
set @q10 = ';
if '+ CAST(@saveChanges as varchar(10)) + '=1 begin
	DBCC DBREINDEX(['+@TableName+'])
	exec dbo.AssetAudit_Rebuild
	DBCC DBREINDEX([AssetAudit])
end'
exec(@q10)

FINISHED:
if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:

drop table #bad
drop table #suspect
drop table #assets