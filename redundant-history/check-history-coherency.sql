set nocount on
create table #results (Asset sysname not null, [ID-Prior] int, [AuditBegin-Prior] int, [AuditEnd-Prior] int, [Sequence-Prior] int, [ID-Next] int, [AuditBegin-Next] int, [AuditEnd-Next] int, [Sequence-Next] int)
declare @now sysname, @hist sysname, @andColsEqual varchar(max)
declare C cursor local fast_forward for

	select H.TABLE_NAME hist
	from INFORMATION_SCHEMA.TABLES H 
	where H.TABLE_TYPE<>'VIEW'
		and 4=(select count(*) from INFORMATION_SCHEMA.COLUMNS C where C.TABLE_NAME=H.TABLE_NAME and COLUMN_NAME in ('ID','AssetType','AuditBegin','AuditEnd'))

open C
while 1=1 begin
	fetch next from C into @hist
	if @@FETCH_STATUS<>0 break

	declare @sql varchar(max); select @sql = '
		;with H as (
			select ID, AuditBegin, AuditEnd, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
			from dbo.[{hist}]
		)
		insert #results
		select ''{hist}'' Asset, *
		from H A left join H B on A.ID=B.ID and A.R+1=B.R
		where isnull(A.AuditEnd, -1)<>isnull(B.AuditBegin, -1)'

	select @sql = REPLACE(@sql, '{hist}', @hist)

	--print(@sql)
	exec(@sql)

end
close C; deallocate c


if 0<(select count(*) from #results) begin
	raiserror('History is not coherent! See results.',16,1)
	select * from #results
end else
	print 'History is coherent'
	
drop table #results
