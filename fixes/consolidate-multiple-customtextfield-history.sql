/*
 *	Consolidate custom field history records, on configurable time threshold (@timeThreshold) in minutes.
 *  Custom field Table also configurable (@customFieldTable).
 *  Works for ALL Custom Tables EXCEPT CustomRelation
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1;
declare @customFieldTable varchar(100); --set @customFieldTable = 'dbo.CustomText';
declare @fieldName varchar(201); --set @fieldName = 'Custom_ExampleFieldName';
declare @timeThreshold int;

set @timeThreshold = 5

create table #customfield(ID int not null, CurrentAuditID int not null, NextAuditID int not null)
create table #suspect(ID int not null, CurrentAuditID int not null, NextAuditID int not null)
create table #bad(ID int not null, CurrentAuditID int not null, NextAuditID int not null)

set nocount on; begin tran; save tran TX

-- Custom Field Rows
declare @q1 varchar(max);
select @q1 = ';
with H as (
	select AA.ID, AA.AssetType, AuditID, R=ROW_NUMBER() OVER(partition by AA.ID, AA.AssetType order by AuditID)
	from dbo.AssetAudit AA
)
insert #customfield(ID, CurrentAuditID, NextAuditID)
select aH.ID, aH.AuditID, bH.AuditID
from H as aH
join ' + @customFieldTable + ' cField on cField.ID=aH.ID and aH.AuditID = cField.AuditBegin
join H as bH on bH.ID=aH.ID and bH.R=aH.R+1
join ' + @customFieldTable + ' bCF on bCF.ID=bH.ID and bH.AuditID = bCF.AuditBegin'

-- Consecutive Custom Field value changes
declare @q2 varchar(max);
select @q2 = ';
insert #suspect(ID, CurrentAuditID, NextAuditID)
select Assets.ID, Assets.CurrentAuditID, Assets.NextAuditID
from #customfield as Assets
join ' + @customFieldTable + ' currentCF on currentCF.ID=Assets.ID and currentCF.AuditBegin=Assets.CurrentAuditID
join ' + @customFieldTable + ' nextCF on nextCF.ID=Assets.ID and nextCF.AuditBegin=Assets.NextAuditID
join dbo.[Audit] currentA on currentA.ID = Assets.CurrentAuditID
join dbo.[Audit] nextA on nextA.ID = Assets.NextAuditID
WHERE
currentCF.[Definition] = ''' + @fieldName + ''' AND nextCF.[Definition] = ''' + @fieldName + ''' -- Targetted field type
AND ISNULL(currentA.[ChangedByID] ,-1) = ISNULL(nextA.[ChangedByID],-1)  -- Consecutive changes from the same user
AND DATEDIFF(mi,currentA.[ChangeDateUTC] ,nextA.[ChangeDateUTC]) <= ' + CAST(@timethreshold as varchar(10)) + ' --Time threshold / period / lapse.
AND	ISNULL(currentCF.[Value],-1) != ISNULL(nextCF.[Value],-1) --Value has changed'

-- consecutive redundant CustomText values
declare @q3 varchar(max);
select @q3 = ';
insert #bad(ID, CurrentAuditID, NextAuditID)
select _.ID, CurrentAuditID, NextAuditID
from #suspect _
join ' + @customFieldTable + ' A on A.ID=_.ID and A.AuditBegin=_.CurrentAuditID
join ' + @customFieldTable + ' B on B.ID=_.ID and B.AuditBegin=_.NextAuditID
join ' + @customFieldTable + ' C on C.ID=_.ID and C.AuditEnd=_.CurrentAuditID AND ISNULL(C.[Value],-1) != ISNULL(A.[Value],-1)'

-- rows to purge
declare @q4 varchar(max);
select @q4 = ';
select cf.ID, cf.AuditBegin, a.ChangedByID, a.ChangeDateUTC
from #bad b
join ' + @customFieldTable + ' cf ON cf.ID=b.ID and cf.AuditBegin=b.CurrentAuditID
join dbo.[Audit] a on a.ID = b.CurrentAuditID'

-- purge redundant rows
declare @q5 varchar(max);
select @q5 = ';
delete ' + @customFieldTable +
' from #bad
where ' + @customFieldTable + '.ID=#bad.ID and (' + @customFieldTable + '.AuditBegin=#bad.CurrentAuditID)'

declare @error int, @rowcount int

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d CustomField value historical records consolidated', 0, 1, @rowcount) with nowait

if @rowcount=0 goto FINISHED

-- re-stitch CustomField history
declare @q6 varchar(max)
select @q6 = ';
with H as (
	select ID, AuditBegin, AuditEnd, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
	from ' + @customFieldTable +
')
update ' + @customFieldTable + ' set AuditEnd=B.AuditBegin
from H A
left join H B on A.ID=B.ID and A.R+1=B.R
where ' + @customFieldTable + '.ID=A.ID and ' + @customFieldTable + '.AuditBegin=A.AuditBegin
	and isnull(A.AuditEnd,-1)<>isnull(B.AuditBegin,-1)'

--print @q1 + @q2 + @q3 + @q4 + @q5 + @q6
exec(@q1 + @q2 + @q3 + @q4 + @q5 + @q6)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d CustomField history records restitched', 0, 1, @rowcount) with nowait

declare @q7 varchar(max);
set @q7 = ';
if '+ CAST(@saveChanges as varchar(10)) + '=1 begin
	DBCC DBREINDEX([' + @customFieldTable + '])

	exec dbo.AssetAudit_Rebuild
	DBCC DBREINDEX([AssetAudit])
end'
exec(@q7);

FINISHED:
if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:

drop table #bad
drop table #suspect
drop table #customfield