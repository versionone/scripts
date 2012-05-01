/*	
 *	Consolidate consecutive identical historical records.
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

create table #results (Asset sysname not null, [rowcount] int not null, error int not null)
declare @now sysname, @hist sysname, @cols varchar(max), @colsEqual varchar(max)
declare C cursor local fast_forward for
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

open C
while 1=1 begin
	fetch next from C into @now, @hist, @cols, @colsEqual
	if @@FETCH_STATUS<>0 break

	declare @sql varchar(max); select @sql = '
		declare @error int, @rowcount int

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
		insert #results values(''{hist}'', @rowcount, @error)
		
		if @rowcount>0 begin
			;with H as (
				select ID, AuditBegin, AuditEnd, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
				from dbo.[{hist}]
			)
			update dbo.[{hist}] set AuditEnd=B.AuditBegin
			from H A
			left join H B on A.ID=B.ID and A.R+1=B.R
			where [{hist}].ID=A.ID and [{hist}].AuditBegin=A.AuditBegin
				and isnull(A.AuditEnd,-1)<>isnull(B.AuditBegin,-1)
				
			alter table dbo.[{now}] disable trigger all

			update dbo.[{now}] set AuditBegin=[{hist}].AuditBegin 
			from dbo.[{hist}]
			where [{hist}].ID=[{now}].ID and [{hist}].AuditEnd is null and [{hist}].AuditBegin<>[{now}].AuditBegin

			alter table dbo.[{now}] enable trigger all
		end'
		
	select @sql = REPLACE(@sql, '{now}', @now)
	select @sql = REPLACE(@sql, '{hist}', @hist)
	select @sql = REPLACE(@sql, '{colsEqual}', @colsEqual)
	select @sql = REPLACE(@sql, '{cols}', @cols)

	--print(@sql)
	exec(@sql)
	
	select @error=error, @rowcount=[rowcount] from #results where Asset=@hist
	if @error<>0 break
	if @rowcount>0 begin
		print @rowcount + ' ' + @hist + ' historical records consolidated'

		if @saveChanges=1 exec('DBCC DBREINDEX([' + @hist + '])')
	end
end

close C; deallocate C

/* after every modifying statement, check for errors; optionally, emit status */
select @rowcount=sum([rowcount]), @error=sum(error) from #results
select * from #results
drop table #results

if @error<>0 goto ERR
print '-------------'
print @rowcount + ' total records consolidated'

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: