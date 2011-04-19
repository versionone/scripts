begin tran

set nocount on
declare @entity varchar(8000), @history varchar(8000)
declare C cursor local fast_forward for
	select TABLE_NAME Entity, left(TABLE_NAME, len(TABLE_NAME)-4) History
	from INFORMATION_SCHEMA.TABLES
	where TABLE_SCHEMA='dbo' and TABLE_NAME like '%_Now' and TABLE_NAME<>'Access_Now' and TABLE_TYPE<>'VIEW'
open C
while 1=1 begin
	fetch next from C into @entity, @history
	if @@FETCH_STATUS<>0 break

	declare @sql varchar(8000),@wherecols varchar(8000)
	select @wherecols=''
	select
		@wherecols=@wherecols+char(10)+' and (one.['+COLUMN_NAME+']=two.['+COLUMN_NAME+'] or (one.['+COLUMN_NAME+'] is null and two.['+COLUMN_NAME+'] is null))'
	from INFORMATION_SCHEMA.COLUMNS
	where COLUMN_NAME not in('ID','AssetType','AuditBegin','EffectiveViewRights','EffectiveUpdateRights','EffectiveUpdatePrivileges') and TABLE_SCHEMA='dbo' and TABLE_NAME=@entity

	select @sql='set nocount on
while 0<(
	select count(*)
	from dbo.['+@history+'] one, dbo.['+@history+'] two
	where two.ID=one.ID and two.AuditBegin=one.AuditEnd'+@wherecols+'
) begin
	declare @id int, @begin int, @end int
	declare C cursor forward_only dynamic for
		select one.ID, one.AuditBegin, one.AuditEnd
		from dbo.['+@history+'] one, dbo.['+@history+'] two
		where two.ID=one.ID and two.AuditBegin=one.AuditEnd'+@wherecols+'
	open C
	while 1=1 begin
		fetch next from C into @id, @begin, @end
		if @@FETCH_STATUS<>0 break

		delete dbo.['+@history+'] where ID=@id and AuditBegin=@begin
		update dbo.['+@history+'] set AuditBegin=@begin where ID=@id and AuditBegin=@end
	end
	close C
	deallocate C
end

alter table dbo.['+@entity+'] disable trigger all
update dbo.['+@entity+'] set AuditBegin=h.AuditBegin from dbo.['+@history+'] h where h.ID=dbo.['+@entity+'].ID and AuditEnd is null and h.AuditBegin<>dbo.['+@entity+'].AuditBegin
alter table dbo.['+@entity+'] enable trigger all'

	exec(@sql);
	print @sql
end
close C
deallocate C

--commit
rollback