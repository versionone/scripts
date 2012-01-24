set nocount on
create table #results (Asset sysname not null, [History ID] int, [History AuditBegin] int, [Now ID] int)
declare @now sysname, @hist sysname, @andColsEqual varchar(max)
declare C cursor local fast_forward for

	select N.TABLE_NAME nowTable, H.TABLE_NAME histTable, 
		andColsEqual = 
			(
				select REPLACE(' and (H.{col}=N.{col} or (H.{col} is null and N.{col} is null))', '{col}', quotename(COLUMN_NAME))
				from INFORMATION_SCHEMA.COLUMNS C 
				where C.TABLE_NAME=H.TABLE_NAME
					and COLUMN_NAME not in ('ID','AssetType','AuditBegin','AuditEnd')
				for xml path('')
			)
	from INFORMATION_SCHEMA.TABLES N
	join INFORMATION_SCHEMA.TABLES H on H.TABLE_NAME+'_Now' = N.TABLE_NAME
	where N.TABLE_TYPE<>'VIEW' and H.TABLE_TYPE<>'VIEW'

open C
while 1=1 begin
	fetch next from C into @now, @hist, @andColsEqual
	if @@FETCH_STATUS<>0 break

	declare @sql varchar(max); select @sql = '
		insert #results(Asset, [History ID], [History AuditBegin], [Now ID])
		select ''{hist}'', H.ID, H.AuditBegin, N.ID
		from dbo.[{hist}] H 
		full outer join dbo.[{now}] N on H.ID=N.ID and H.AuditBegin=N.AuditBegin
			{andColsEqual}
		where (H.ID is null or N.ID is null) and H.AuditEnd is null'

	select @sql = REPLACE(@sql, '{now}', @now)
	select @sql = REPLACE(@sql, '{hist}', @hist)
	select @sql = REPLACE(@sql, '{andColsEqual}', @andColsEqual)

	--print(@sql)
	exec(@sql)

end
close C; deallocate c


if 0<(select count(*) from #results) begin
	raiserror('"Now" is not consistent with "history"! See results.',16,1)
	select * from #results
end else
	print '"Now" is consistent with "history"'
	
drop table #results
