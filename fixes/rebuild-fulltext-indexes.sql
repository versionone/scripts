-- Disable Full Text Indexes
declare @sql varchar(1000); select @sql = ''
select @sql = @sql + 'ALTER FULLTEXT INDEX ON ' + QUOTENAME(OBJECT_NAME(x.object_id)) + ' DISABLE;' from sys.fulltext_indexes x
EXEC (@sql)
GO

if DATABASEPROPERTY(DB_NAME(), 'IsFulltextEnabled') <> 1 exec sp_fulltext_database @action='enable'
GO

exec dbo._DropFullTextCatalogs
exec dbo._AddFullTextIndex 'String.Value'
exec dbo._AddFullTextIndex 'LongString.Value'
GO

-- Enable Full Text Indexes
declare @sql varchar(1000); select @sql = ''
select @sql = @sql + 'ALTER FULLTEXT INDEX ON ' + QUOTENAME(OBJECT_NAME(x.object_id)) + ' ENABLE;' from sys.fulltext_indexes x
EXEC (@sql)
GO