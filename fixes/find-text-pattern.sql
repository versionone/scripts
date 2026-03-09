/*
 *	Find instances of text patterns in the database.
 *
 * INSTRUCTIONS:
 *
 * 1. Set the patterns in #SearchPattern (below)
 *     You may define as many patterns as necessary.
 *     A record will be flagged if it matches at least one pattern.
 *
 * 2. Run the script
 *     The number of flagged records in each table will be printed.
 *     No changes to the database are made.
 */

create table #SearchPattern (Pattern nvarchar(max) not null)
insert into #SearchPattern (Pattern) values
	--------------------------------------------------
	-- Edit the patterns here. Each row is a wildcard pattern to search for.
	--------------------------------------------------
	(N'%Pattern 1%'),
	(N'%Pattern 2%')
	--------------------------------------------------
GO

create proc #Search(
	@table sysname,
	@column sysname
) as
begin

declare @sql nvarchar(max), @rowcount int

;with X as (select
	TableName = quotename(t.name),
	Value =  case when ty.name in (N'char', N'varchar', N'nchar', N'nvarchar', N'text', N'ntext')
		then quotename(c.name)
		else 'cast(' + quotename(c.name) + ' as varchar(max))' end,
	Collation = case when ty.name in (N'char', N'varchar', N'nchar', N'nvarchar', N'text', N'ntext')
		then 'Latin1_General_100_CI_AS'
		else 'Latin1_General_100_CI_AS_SC_UTF8' end
	from sys.tables t
	join sys.columns c on c.object_id=t.object_id
	join sys.types ty on ty.user_type_id=c.user_type_id
	where t.schema_id = SCHEMA_ID('dbo') and t.name=@table and c.name=@column
)
select @sql = N'
	select @rowcount=count(*) from dbo.' + TableName + '
	where exists (select * from #SearchPattern
		where ' + Value + ' collate ' + Collation + '
		like Pattern collate ' + Collation + ')
	'
from X

--print @sql
exec sp_executesql @sql, N'@rowcount int output', @rowcount output
raiserror('  %8d %s.%s', 0, 1, @rowcount, @table, @column) with nowait

end
GO

set nocount on
declare @rowcount int

raiserror('Flagged records:', 0, 1) with nowait

exec #Search 'String', 'Value'
exec #Search 'LongString', 'Value'
exec #Search 'BaseAssetTaggedWith', 'Value'
exec #Search 'CustomTag', 'Value'
exec #Search 'Activity', 'Body'
exec #Search 'Commits', 'Payload'
exec #Search 'WebhookEvents', 'Payload'
exec #Search 'Config', 'Value'
exec #Search 'Localization', 'Value'
exec #Search 'PublishedPayload', 'Value'
exec #Search 'PublishedPayload', 'Description'
exec #Search 'Snapshots', 'Payload'

GO
drop proc #Search
drop table #SearchPattern
