/*	
 *	Stitch back together corrupted history.
 *	
 *	@histTable: name of the historical table to fix
 *	@saveChanges: must be set=1 to commit changes, otherwise everything rolls back
 */
declare @histTable sysname; set @histTable='Access'
declare @saveChanges bit; --set @saveChanges = 1

declare @nowTable sysname; set @nowTable=@histTable+'_Now'
BEGIN
	if not exists (select * from INFORMATION_SCHEMA.TABLES where TABLE_NAME=@histTable) begin
		raiserror('No such table [%s]',16,1, @histTable)
		goto DONE
	end
	
	if 3<>(select count(*) from INFORMATION_SCHEMA.COLUMNS 
		where TABLE_NAME=@histTable
		and COLUMN_NAME in ('ID', 'AuditBegin', 'AuditEnd')) 
	begin
		raiserror('[%s] is not a historical table',16,1, @histTable)
		goto DONE
	end
	
	if not exists (select * from INFORMATION_SCHEMA.TABLES where TABLE_NAME=@nowTable) begin
		raiserror('No such table [%s]',16,1, @nowTable)
		goto DONE
	end
	
	if 2<>(select count(*) from INFORMATION_SCHEMA.COLUMNS 
		where TABLE_NAME=@nowTable
		and COLUMN_NAME in ('ID', 'AuditBegin')) 
	begin
		raiserror('[%s] is not an asset table',16,1, @nowTable)
		goto DONE
	end
END

declare @error int, @rowcount varchar(20)
declare @sqlTemplate varchar(max), @sql varchar(max)
set nocount on; begin tran; save tran TX

select @sqlTemplate = 
'with A as (
	select ID, AuditBegin, AuditEnd, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
	from dbo.[{hist}]
)
update dbo.[{hist}] set AuditEnd=C.AuditBegin
from A B
left join A C on B.ID=C.ID and B.R+1=C.R
where [{hist}].ID=B.ID and [{hist}].AuditBegin=B.AuditBegin
	and isnull(B.AuditEnd,-1)<>isnull(C.AuditBegin,-1)'
select @sql = REPLACE(@sqlTemplate, '{hist}', @histTable)
--print(@sql)
exec(@sql)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' historical ' + @histTable + ' records fixed'


select @sqlTemplate = 
'alter table dbo.[{now}] disable trigger all'
select @sql = REPLACE(@sqlTemplate, '{now}', @nowTable)
--print(@sql)
exec(@sql)

select @sqlTemplate = 
'update dbo.[{now}] set AuditBegin=[{hist}].AuditBegin 
from dbo.[{hist}]
where [{hist}].ID=[{now}].ID and [{hist}].AuditEnd is null and [{hist}].AuditBegin<>[{now}].AuditBegin'
select @sql = REPLACE(REPLACE(@sqlTemplate, '{hist}', @histTable), '{now}', @nowTable)
--print(@sql)
exec(@sql)

select @rowcount=@@ROWCOUNT, @error=@@ERROR

select @sqlTemplate = 
'alter table dbo.[{now}] enable trigger all'
select @sql = REPLACE(@sqlTemplate, '{now}', @nowTable)
--print(@sql)
exec(@sql)

if @error<>0 goto ERR
print @rowcount + ' ' + @nowTable + ' records fixed'


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: