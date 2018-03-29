declare @sql nvarchar(max); select @sql=''
select @sql=@sql+'; alter fulltext index on '+OBJECT_SCHEMA_NAME(object_id)+'.'+OBJECT_NAME(object_id)+' set stoplist=off'
from sys.fulltext_indexes where stoplist_id is not null
print(@sql)
exec(@sql)
