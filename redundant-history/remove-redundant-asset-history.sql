/*	
 *	Consolidate consecutive identical historical records.
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @rows int = 0

declare @sqlTemplate varchar(max); select @sqlTemplate = '
	declare @error int, @rowcount int
	begin tran; save tran TX2

	;with H as (
		select ID, AuditBegin, R=ROW_NUMBER() OVER(partition by ID order by AuditBegin)
			{cols}
		from dbo.[{hist}]
	)
	delete dbo.[{hist}]
	from H A
	join H B on A.ID=B.ID and A.R+1=B.R
	where [{hist}].ID=B.ID and [{hist}].AuditBegin=B.AuditBegin
		{colsEqual}

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
		
	if @rowcount>0 begin
		select @rows = @rows + @rowcount
		raiserror(''%d {hist} historical records deleted'', 0, 1, @rowcount) with nowait

		;with H as (
			select ID, AuditBegin, AuditEnd, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
			from dbo.[{hist}]
		)
		update dbo.[{hist}] set AuditEnd=B.AuditBegin
		from H A
		left join H B on A.ID=B.ID and A.R+1=B.R
		where [{hist}].ID=A.ID and [{hist}].AuditBegin=A.AuditBegin
			and isnull(A.AuditEnd,-1)<>isnull(B.AuditBegin,-1)

		select @rowcount=@@ROWCOUNT, @error=@@ERROR
		if @error<>0 goto ERR
		raiserror(''%d {hist} historical records stitched'', 0, 2, @rowcount) with nowait
				
		alter table dbo.[{now}] disable trigger all

		update dbo.[{now}] set AuditBegin=[{hist}].AuditBegin 
		from dbo.[{hist}]
		where [{hist}].ID=[{now}].ID and [{hist}].AuditEnd is null and [{hist}].AuditBegin<>[{now}].AuditBegin

		select @rowcount=@@ROWCOUNT, @error=@@ERROR
		alter table dbo.[{now}] enable trigger all

		if @error<>0 goto ERR
		raiserror(''%d {now} records synced'', 0, 3, @rowcount) with nowait

		insert #sql values(''raiserror(''''reindex {hist}'''', 0, 4) with nowait; dbcc dbreindex (''''dbo.[{hist}]'''')'')

		if ({saveChanges} = 1) goto OK
		raiserror(''To commit changes, set @saveChanges=1'',16,254) with nowait
		ERR: raiserror(''Rolling back changes'', 0, 255) with nowait; rollback tran TX2
	end
	OK: commit
'

set nocount on
create table #sql (sql varchar(max) not null)

insert #sql
select REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@sqlTemplate, '{now}', nowTable), '{hist}', histTable), '{colsEqual}', colsEqual), '{cols}', cols), '{saveChanges}', isnull(@saveChanges, 0))
from (
	select N.TABLE_NAME nowTable, H.TABLE_NAME histTable, 
		cols = 
			(
				select ','+quotename(COLUMN_NAME)
				from INFORMATION_SCHEMA.COLUMNS C 
				where C.TABLE_NAME=N.TABLE_NAME
					and COLUMN_NAME not in ('ID','AssetType','AuditBegin')
				for xml path('')
			),
		colsEqual = 
			(
				select REPLACE(' and (A.{col}=B.{col} or (A.{col} is null and B.{col} is null))', '{col}', quotename(COLUMN_NAME))
				from INFORMATION_SCHEMA.COLUMNS C 
				where C.TABLE_NAME=N.TABLE_NAME
					and COLUMN_NAME not in ('ID','AssetType','AuditBegin')
				for xml path('')
			)
	from INFORMATION_SCHEMA.TABLES N
	join INFORMATION_SCHEMA.TABLES H on H.TABLE_NAME+'_Now' = N.TABLE_NAME
	where N.TABLE_TYPE<>'VIEW' and H.TABLE_TYPE<>'VIEW'
		and H.TABLE_NAME not in (
			-- Access has its own unique definition of "redundant"
			'Access', 
			
			-- Skip meta assets
			'AssetType', 'AttributeDefinition', 'BaseRule', 'BaseSyntheticAttributeDefinition', 'DefaultRule', 'EventDefinition', 'ExecuteSecurityCheckAttributeDefinition', 'InsertUpdateRule', 'ManyToManyRelationDefinition', 'Operation', 'Override', 'RelationDefinition', 
			
			-- Skip "system" assets
			'Role', 'State'
		)
)_

declare @sql varchar(max)
declare C cursor local fast_forward for select sql from #sql
open C
while 1=1 begin
	fetch next from C into @sql
	if @@FETCH_STATUS<>0 break

	--print(@sql)
	exec(@sql)
end

close C; deallocate C
--select * from #sql

drop table #sql
