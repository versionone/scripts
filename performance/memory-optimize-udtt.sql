/*
 *	This script replaces the user-defined table types in the current database
 *	with memory-optimized versions.
 *	
 *	It will create a MEMORY_OPTIMIZED_DATA filegroup, and a container within it,
 *	if such does not already exist.
 *	
 *	Some UDTTs may require SQL Server 2016 to be memory-optimized.
 */

-- enable memory-optimized objects
set nocount on
declare @db_name sysname = DB_NAME()
declare @filegroup_name sysname = N'MEMOPT', @data_space_id int

declare @add_filegroup nvarchar(max) = N'
	ALTER DATABASE [@db_name] 
	ADD FILEGROUP [@filegroup_name] 
	CONTAINS MEMORY_OPTIMIZED_DATA'

if not exists (select * from sys.data_spaces where type='FX') begin
	select @add_filegroup = replace(replace(@add_filegroup, 
		'[@filegroup_name]', quotename(@filegroup_name)), 
		'[@db_name]', quotename(@db_name))
	print(@add_filegroup)
	exec(@add_filegroup)
end

select @filegroup_name = name, @data_space_id = data_space_id
from sys.data_spaces where type='FX'

declare @file_name sysname = @db_name + '_memopt1'
declare @path nvarchar(260)

select top(1) @path=left(physical_name, len(physical_name) - charindex('\', reverse(physical_name)))
from sys.database_files
where type_desc='ROWS'
order by file_id

declare @add_file nvarchar(max) = N'
	ALTER DATABASE [@db_name] 
	ADD FILE (
		name=''@file_name'', 
		filename=''@path\@file_name''
	) TO FILEGROUP [@filegroup_name]'

if not exists (select * from sys.database_files where data_space_id=@data_space_id) begin
	select @add_file = replace(replace(replace(replace(@add_file,
		'[@filegroup_name]', quotename(@filegroup_name)), 
		'[@db_name]', quotename(@db_name)),
		'@file_name', @file_name),
		'@path', @path)
	print(@add_file)
	exec(@add_file)
end

GO

set nocount on
declare @sqls table(n int identity, sql nvarchar(max) not null)
declare @sql nvarchar(max)

-- find non-memory-optimized UDTTs
declare @tt table(
	schema_id int not null,
	name sysname not null, 
	user_type_id int not null,
	table_type_object_id int not null
)

insert @tt(schema_id, name, user_type_id, table_type_object_id)
select schema_id, name, user_type_id, type_table_object_id
from sys.table_types
where is_user_defined=1 and is_memory_optimized=0

-- find dependant procs
declare @proc table(id int not null)

insert @proc(id)
select distinct referencing_id
from @tt
join sys.sql_expression_dependencies on referenced_id=user_type_id

-- drop dependant procs
insert @sqls(sql)
select N'drop proc ' + quotename(OBJECT_SCHEMA_NAME(id)) + N'.' + quotename(OBJECT_NAME(id))
from @proc
order by id asc

-- drop non-memory-optimized UDTTs
insert @sqls(sql)
select N'drop type ' + quotename(SCHEMA_NAME(schema_id)) + N'.' + quotename(name)
from @tt

-- create memory-optimized UUDTs
declare @schema_id int, @type_name sysname, @object_id int
declare A cursor local fast_forward for
	select schema_id, name, table_type_object_id from @tt
open A; while 1=1 begin
	fetch next from A into @schema_id, @type_name, @object_id
	if @@FETCH_STATUS<>0 break

	-- declare the type
	select @sql = N'create type ' + 
		quotename(SCHEMA_NAME(@schema_id)) + N'.' + quotename(@type_name) + 
		' as table('

	-- define columns
	declare @col_name sysname, @utype_name sysname, @max_length smallint, @collation_name sysname, @is_nullable bit, @is_identity bit, @definition nvarchar(max)
	declare B cursor local fast_forward for
		select c.name, t.name, c.max_length, c.collation_name, c.is_nullable, c.is_identity, dc.definition
		from sys.columns c
		join sys.types t on t.user_type_id=c.user_type_id
		left join sys.default_constraints dc
			on dc.parent_object_id=c.object_id and dc.parent_column_id=c.column_id
		where c.object_id=@object_id
	open B; while 1=1 begin
		fetch next from B into @col_name, @utype_name, @max_length, @collation_name, @is_nullable, @is_identity, @definition
		if @@FETCH_STATUS<>0 break

		select @sql = @sql + N'
	' +
			quotename(@col_name) + N' ' + @utype_name +
			case when @utype_name in ('binary','varbinary','char','varchar','nchar','nvarchar') then
				case when @max_length=-1 then 
					N'(max)' 
				else
					N'(' + cast(@max_length as varchar(10)) + N')' 
				end
			else
				N''
			end +
			case when @collation_name is not null then N' collate ' + @collation_name else N'' end +
			case when @is_nullable=0 then N' not' else N'' end + N' null' +
			case when @is_identity=1 then N' identity' else N'' end +
			case when @definition is not null then N' default'+@definition else '' end +
			N','
	end; close B; deallocate B

	-- define indexes
	declare @index_id int, @is_primary_key bit
	declare C cursor local fast_forward for
		select index_id, is_primary_key
		from sys.indexes
		where object_id=@object_id
		order by index_id
	open C; while 1=1 begin
		fetch next from C into @index_id, @is_primary_key
		if @@FETCH_STATUS<>0 break

		select @sql = @sql + N'
	' +
			case when @is_primary_key=1 then N'primary key nonclustered(' else N'nonclustered index(' end

		-- index columns
		declare @column_id int
		declare D cursor local fast_forward for
			select column_id
			from sys.index_columns
			where object_id=@object_id and index_id=@index_id and is_included_column=0
			order by column_id
		open D; while 1=1 begin
			fetch next from D into @column_id
			if @@FETCH_STATUS<>0 break
			select @sql = @sql + COL_NAME(@object_id, @column_id) + N', '
		end; close D; deallocate D

		select @sql = left(@sql, len(@sql)-1) + N'),'
	end; close C; deallocate C

	select @sql = left(@sql, len(@sql)-1) + N'
) with (memory_optimized=on)'
	insert @sqls(sql) values(@sql)
end; close A; deallocate A

-- recreate dropped procs
insert @sqls(sql)
select OBJECT_DEFINITION(id)
from @proc
order by id desc

declare X cursor local fast_forward for
	select sql from @sqls order by n
open X; while 1=1 begin
	fetch next from X into @sql
	if @@FETCH_STATUS<>0 break
	print(@sql)
	--exec(@sql)
end; close X; deallocate X

