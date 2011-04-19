begin tran

set nocount on
declare @custom varchar(8000)
declare C cursor local fast_forward for
	select TABLE_NAME Custom
	from INFORMATION_SCHEMA.TABLES
	where TABLE_SCHEMA='dbo' and TABLE_NAME like 'Custom%' and TABLE_NAME<>'CustomRelation' and TABLE_TYPE<>'VIEW'
open C
while 1=1 begin
	fetch next from C into @custom
	if @@FETCH_STATUS<>0 break

	declare @sql varchar(8000),@wherecols varchar(8000)
	select @wherecols=' and one.[Value]=two.[Value]'

	select @sql='set nocount on
select '''+@custom+''' TableName, Total, Duplicate, Duplicate*100.0/nullif(Total,0) RedundancyPercentage from (select
	(select COUNT(*) from dbo.['+@custom+'] one join dbo.['+@custom+'] two on two.ID=one.ID and two.Definition=one.Definition and two.AuditBegin=one.AuditEnd and two.Value=one.Value) Duplicate,
	(select COUNT(*) from dbo.['+@custom+']) Total) _
while 0<(
	select count(*)
	from dbo.['+@custom+'] one, dbo.['+@custom+'] two
	where two.ID=one.ID and two.Definition=one.Definition and two.AuditBegin=one.AuditEnd and one.[Value]=two.[Value]
) begin
	declare @id int, @definition varchar(8000), @begin int, @end int
	declare C cursor forward_only dynamic for
		select one.ID, one.Definition, one.AuditBegin, one.AuditEnd
		from dbo.['+@custom+'] one, dbo.['+@custom+'] two
		where two.ID=one.ID and two.Definition=one.Definition and two.AuditBegin=one.AuditEnd and one.[Value]=two.[Value]
	open C
	while 1=1 begin
		fetch next from C into @id, @definition, @begin, @end
		if @@FETCH_STATUS<>0 break

		delete dbo.['+@custom+'] where ID=@id and AuditBegin=@begin and Definition=@definition
		update dbo.['+@custom+'] set AuditBegin=@begin where ID=@id and AuditBegin=@end and Definition=@definition
	end
	close C
	deallocate C
end
select '''+@custom+''' TableName, Total, Duplicate, Duplicate*100.0/nullif(Total,0) RedundancyPercentage from (select
	(select COUNT(*) from dbo.['+@custom+'] one join dbo.['+@custom+'] two on two.ID=one.ID and two.Definition=one.Definition and two.AuditBegin=one.AuditEnd and two.Value=one.Value) Duplicate,
	(select COUNT(*) from dbo.['+@custom+']) Total) _
'

	print @sql
	exec(@sql);
end
close C
deallocate C

exec dbo.AssetAudit_Rebuild


--commit
rollback