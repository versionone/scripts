
create table #indexes(
	database_id smallint, 
	object_id int, 
	index_id int, 
	database_name sysname,
	table_name sysname,
	index_name sysname null,
	table_type_desc nvarchar(60),
	index_type_desc nvarchar(60))

exec V1_DB_Maintenance.util.foreachdb '
	insert #indexes 
	select 
		DB_ID(''?'') database_id, 
		i.object_id, 
		i.index_id, 
		''?'' database_name,
		o.name table_name, 
		i.name index_name,
		o.type_desc table_type_desc,
		i.type_desc index_type_desc
	from [?].sys.indexes i
	join [?].sys.objects o on o.object_id=i.object_id
	where o.type_desc=''USER_TABLE'' --and i.type_desc=''NONCLUSTERED''
	',
	@user_only=1 ,@suppress_quotename=1
	--,@print_command_only=1

--select * from #indexes

select * from (
	select  
		table_name, 
		index_name, 
		sum(user_seeks) total_user_seeks, 
		sum(user_scans) total_user_scans, 
		sum(user_lookups) total_user_lookups, 
		sum(user_updates) total_user_updates 
	from sys.dm_db_index_usage_stats S 
	join #indexes AS I ON I.database_id=S.database_id and I.object_id = S.object_id and I.index_id = S.index_id 
	group by table_name, index_name
)_
order by total_user_seeks+total_user_scans+total_user_lookups, total_user_updates desc

drop table #indexes
