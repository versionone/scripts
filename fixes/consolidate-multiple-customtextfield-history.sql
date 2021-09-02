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
declare @fieldName varchar(201); --set @fieldName = 'Story.Custom_ConsolidateMe';
declare @timeThreshold int;

set @timeThreshold = 5

create table #customfield(ID int not null, CurrentAuditID int not null, NextAuditID int not null, Definition varchar(201) collate Latin1_General_BIN not null)
create table #donotpurge(ID int not null, AuditBegin int not null, AuditEnd int not null, Definition varchar(201) collate Latin1_General_BIN not null)
create table #bad(ID int not null, CurrentAuditID int not null, NextAuditID int not null, Definition varchar(201) collate Latin1_General_BIN not null)

set nocount on; begin tran; save tran TX

-- Custom Field Rows and No-Touch Table
-- Will not affect rows whose Audit IDs are not contiguous within the table
declare @q1 varchar(max);
select @q1 = ';
with CFH as (
	select ID, AuditBegin AuditID, Definition, R=ROW_NUMBER() OVER(partition by ID order by AuditBegin)
	from ' + @customFieldTable + ' CF
	where Definition = ''' + @fieldName + '''
)
insert #customfield(ID, CurrentAuditID, NextAuditID, Definition)
select aH.ID, aH.AuditID, bH.AuditID, aH.Definition
from CFH as aH
join CFH as bH on bH.ID=aH.ID and bH.R=aH.R+1

insert #donotpurge(ID, AuditBegin, AuditEnd, Definition)
select CF.ID, CF.AuditBegin, CF.AuditEnd, CF.Definition
from ' + @customFieldTable + ' CF
left join ' + @customFieldTable + ' CF2 on CF2.ID=CF.ID and CF2.Definition=CF.Definition and CF2.AuditBegin=CF.AuditEnd
where CF.Definition = ''' + @fieldName + ''' and CF2.ID is null
'

-- Consecutive Custom Field value changes
declare @q2 varchar(max);
select @q2 = ';
insert #bad(ID, CurrentAuditID, NextAuditID, Definition)
select Assets.ID, Assets.CurrentAuditID, Assets.NextAuditID, Assets.Definition
from #customfield as Assets
join ' + @customFieldTable + ' currentCF on currentCF.ID=Assets.ID and currentCF.AuditBegin=Assets.CurrentAuditID and currentCF.Definition = Assets.Definition
join ' + @customFieldTable + ' nextCF on nextCF.ID=Assets.ID and nextCF.AuditBegin=Assets.NextAuditID and nextCF.Definition = Assets.Definition
join dbo.Audit currentA on currentA.ID = Assets.CurrentAuditID
join dbo.Audit nextA on nextA.ID = Assets.NextAuditID
WHERE
ISNULL(currentA.ChangedByID, -1) = ISNULL(nextA.ChangedByID, -1)  -- Consecutive changes from the same user
AND DATEDIFF(mi, currentA.ChangeDateUTC, nextA.ChangeDateUTC) <= ' + CAST(@timethreshold as varchar(10)) + ' --Time threshold / period / lapse.
AND currentCF.Value != nextCF.Value'

-- rows to purge
declare @q3 varchar(max);
select @q3 = ';
select cf.ID, cf.AuditBegin, a.ChangedByID, a.ChangeDateUTC
from #bad b
join ' + @customFieldTable + ' cf ON cf.ID=b.ID and cf.AuditBegin=b.CurrentAuditID and cf.Definition = b.Definition
join dbo.Audit a on a.ID = b.CurrentAuditID
where not exists (select 1 from #donotpurge dnp where b.ID=dnp.ID and b.CurrentAuditID=dnp.AuditBegin and b.Definition=dnp.Definition)'

-- purge redundant rows
declare @q4 varchar(max);
select @q4 = ';
delete ' + @customFieldTable +
' from #bad
where ' + @customFieldTable + '.ID=#bad.ID and ' + @customFieldTable + '.AuditBegin=#bad.CurrentAuditID and ' + @customFieldTable + '.Definition = #bad.Definition
and not exists (select 1 from #donotpurge dnp where #bad.ID=dnp.ID and #bad.CurrentAuditID=dnp.AuditBegin and #bad.Definition=dnp.Definition)'

declare @error int, @rowcount int

exec(@q1 + @q2 + @q3 + @q4)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d CustomField value historical records consolidated', 0, 1, @rowcount) with nowait

if @rowcount=0 goto FINISHED

-- re-stitch CustomField history
declare @q5 varchar(max)
select @q5 = ';
ALTER TABLE ' + @customFieldTable + ' NOCHECK CONSTRAINT ALL;
with H as (
	select ID, AuditBegin, AuditEnd, Definition, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
	from ' + @customFieldTable + '
	where Definition = ''' + @fieldName + '''
)
update ' + @customFieldTable + ' set AuditEnd=B.AuditBegin
from H A
join H B on A.ID=B.ID and A.R+1=B.R
where ' + @customFieldTable + '.ID=A.ID and ' + @customFieldTable + '.AuditBegin=A.AuditBegin and ' + @customFieldTable + '.Definition = A.Definition
and isnull(A.AuditEnd,-1)<>isnull(B.AuditBegin,-1)
and NOT EXISTS (select 1 from #donotpurge dnp where A.ID=dnp.ID and A.AuditBegin=dnp.AuditBegin and A.Definition=dnp.Definition);
ALTER TABLE ' + @customFieldTable + ' CHECK CONSTRAINT ALL'

exec(@q5)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d CustomField history records restitched', 0, 1, @rowcount) with nowait

if @saveChanges = 1 begin
	declare @q6 varchar(max);
	set @q6 = ';
		DBCC DBREINDEX([' + @customFieldTable + '])

		exec dbo.AssetAudit_Rebuild
		DBCC DBREINDEX([AssetAudit])
	'
	exec(@q6);
end

FINISHED:
if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:

drop table #bad
drop table #donotpurge
drop table #customfield