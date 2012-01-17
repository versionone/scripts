/*	
 *	Stitch back together corrupted history.
 *	
 *	@tablename: name of the historical table to fix
 *	@saveChanges: must be set=1 to commit changes, otherwise everything rolls back
 */
declare @tablename sysname; set @tablename='Access'
declare @saveChanges bit; --set @saveChanges = 1

BEGIN
	if not exists (select * from INFORMATION_SCHEMA.TABLES where TABLE_NAME=@tablename) begin
		raiserror('No such table [%s]',16,1, @tablename)
		goto DONE
	end
	if 3<>(select count(*) from INFORMATION_SCHEMA.COLUMNS 
		where TABLE_NAME=@tablename
		and COLUMN_NAME in ('ID', 'AuditBegin', 'AuditEnd')) 
	begin
		raiserror('[%s] is not a historical table',16,1, @tablename)
		goto DONE
	end
END

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX


declare @sqlTemplate varchar(max), @sql varchar(max)
select @sqlTemplate = 
'with A as (
	select *, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
	from dbo.[{table}]
)
update dbo.[{table}] set AuditEnd=C.AuditBegin
from A B
left join A C on B.ID=C.ID and B.R+1=C.R
where [{table}].ID=B.ID and [{table}].AuditBegin=B.AuditBegin
	and isnull(B.AuditEnd,-1)<>isnull(C.AuditBegin,-1)'

select @sql = REPLACE(@sqlTemplate, '{table}', @tablename)
--print(@sql)
exec(@sql)


/* after every modifying statement, check for errors; optionally, emit status */
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' historical ' + @tablename + ' records fixed'


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: