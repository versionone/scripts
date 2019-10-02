/*
 *	This script drops any memory-optimized user-defined table types 
 *	in the current database
 *	
 *	After this, the database will need to be repaired by running Setup again.
 */

set nocount on
declare @sqls table(n int identity, sql nvarchar(max) not null)
declare @sql nvarchar(max)

-- find memory-optimized UDTTs
declare @tt table(
	schema_id int not null,
	name sysname not null, 
	user_type_id int not null,
	table_type_object_id int not null
)

insert @tt(schema_id, name, user_type_id, table_type_object_id)
select schema_id, name, user_type_id, type_table_object_id
from sys.table_types
where is_user_defined=1 and is_memory_optimized=1

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

-- drop memory-optimized UDTTs
insert @sqls(sql)
select N'drop type ' + quotename(SCHEMA_NAME(schema_id)) + N'.' + quotename(name)
from @tt

declare X cursor local fast_forward for
	select sql from @sqls order by n
open X; while 1=1 begin
	fetch next from X into @sql
	if @@FETCH_STATUS<>0 break
	print(@sql)
	exec(@sql)
end; close X; deallocate X

drop function dbo.Thumbprint
