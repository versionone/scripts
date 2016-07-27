/*
 *	Consolidate duplicate LongString values.
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */

declare @saveChanges bit; -- set @saveChanges = 1

set nocount on

create table #results (tbl sysname not null, [rowcount] int not null, error int not null)

create table #hash (ID int not null, md5 binary(16) not null)
create clustered index ix_hash_md5_id on #hash(md5, ID)

insert #hash(ID, md5)
select ID, md5=sys.fn_repl_hash_binary(cast(cast(Value as nvarchar(max)) as varbinary(max)))
from dbo.LongString

create table #Bad (BadID int not null primary key, GoodID int not null)

insert #Bad(BadID, GoodID)
select me.ID BadID, _.ID GoodID
from dbo.LongString me
join #hash my_hash on my_hash.ID=me.ID
cross apply (
	select top 1 other.ID
	from dbo.LongString other
	join #hash other_hash on other_hash.ID=other.ID
	where other_hash.md5=my_hash.md5 and other.ID<me.ID and cast(other.Value as nvarchar(max))=cast(me.Value as nvarchar(max))
	order by other.ID
) _
insert #results(tbl, [rowcount], error) select '#Bad', @@ROWCOUNT, @@ERROR

drop table #hash

declare @error int, @rowcount varchar(20)
declare @asset sysname, @attr sysname, @tbl sysname

begin tran; save tran TX

declare C cursor local fast_forward for
	select AT.Name, AD.Name
	from dbo.AttributeDefinition_Now AD, dbo.AssetType_Now AT
	where AttributeType='LongText'
	and AT.ID=AD.AssetID
	and NativeValue=0 and AD.IsCustom=0
	-- existing data from former asset types
	union all select 'Note','Content'
	union all select 'Snapshot','Description'

open C
while 1=1 begin
	fetch next from C into @asset, @attr
	if @@FETCH_STATUS<>0 break

	declare @sql varchar(max); select @sql = '
update dbo.[{asset}]
set [{attr}]=GoodID
from #Bad
where [{attr}]=BadID
insert #results(tbl, [rowcount], error) select ''{asset}.{attr}'', @@ROWCOUNT, @@ERROR

alter table dbo.[{asset}_Now] disable trigger all

update dbo.[{asset}_Now]
set [{attr}]=h.[{attr}]
from dbo.[{asset}] h
where h.ID=[{asset}_Now].ID and h.AuditEnd is null and h.[{attr}] is not null and (h.[{attr}]<>[{asset}_Now].[{attr}] or [{asset}_Now].[{attr}] is null)
insert #results(tbl, [rowcount], error) select ''{asset}_Now.{attr}'', @@ROWCOUNT, @@ERROR

alter table dbo.[{asset}_Now] enable trigger all
'
	select @sql = REPLACE(@sql, '{asset}', @asset)
	select @sql = REPLACE(@sql, '{attr}', @attr)

	--print(@sql)
	exec(@sql)

	select @tbl = @asset + '.' + @attr
	select @error=error, @rowcount=[rowcount] from #results where tbl=@tbl
	if @error<>0 break
	if @rowcount>0 begin
		print @rowcount + ' ' + @tbl + ' values updated'

		if @saveChanges=1 exec('DBCC DBREINDEX([' + @asset + '])')
	end

	select @tbl = @asset + '_Now.' + @attr
	select @error=error, @rowcount=[rowcount] from #results where tbl=@tbl
	if @error<>0 break
	if @rowcount>0 begin
		print @rowcount + ' ' + @tbl + ' values updated'

		if @saveChanges=1 exec('DBCC DBREINDEX([' + @asset + '_Now])')
	end
end

close C; deallocate C

update dbo.[CustomLongText]
set [Value]=GoodID
from #Bad
where [Value]=BadID

select @rowcount=@@ROWCOUNT, @error=@@ERROR, @tbl='CustomLongText.Value'
insert #results(tbl, [rowcount], error) select @tbl, @rowcount, @error

if @error=0 and @rowcount>0 begin
		print @rowcount + ' ' + @tbl + ' values updated'

		if @saveChanges=1 exec('DBCC DBREINDEX([CustomLongText])')
end

select @rowcount=sum([rowcount]), @error=sum(error) from #results where tbl<>'#Bad'
if @error<>0 goto ERR
if @rowcount>0 and @saveChanges=1 exec dbo.AssetLongString_Populate
print '-------------'
print @rowcount + ' total records updated'

select * from #results

if @saveChanges=1 goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:

if @saveChanges=1 begin
	begin tran; save tran TX

	delete dbo.LongString from #Bad b where LongString.ID=b.BadID
	select @error=@@ERROR, @rowcount=@@ROWCOUNT
	if @error=0 begin
		print @rowcount + ' redundant LongString records deleted'
		goto CLEANED
	end
	print 'redundant LongString records remain'

	rollback tran TX
	CLEANED: commit
end

drop table #Bad
drop table #results
