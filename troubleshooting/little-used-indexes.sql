select  
	o.name table_name, 
	i.name index_name, 
	user_seeks, 
	user_scans, 
	user_lookups, 
	user_updates 
from sys.dm_db_index_usage_stats S 
join sys.indexes AS I ON I.object_id = S.object_id and I.index_id = S.index_id 
join sys.objects o on o.object_id=i.object_id
where database_id=DB_ID()
order by user_seeks+user_scans+user_lookups, user_updates desc
