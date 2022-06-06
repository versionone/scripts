SELECT snapshot_isolation_state, snapshot_isolation_state_desc, is_read_committed_snapshot_on FROM sys.databases WHERE database_id=DB_ID()

declare @sql nvarchar(max); select @sql=REPLACE('
ALTER DATABASE {db} SET ALLOW_SNAPSHOT_ISOLATION ON
ALTER DATABASE {db} SET SINGLE_USER WITH ROLLBACK IMMEDIATE
ALTER DATABASE {db} SET READ_COMMITTED_SNAPSHOT ON
ALTER DATABASE {db} SET MULTI_USER
', '{db}', QUOTENAME(DB_NAME()))
exec(@sql)

SELECT snapshot_isolation_state, snapshot_isolation_state_desc, is_read_committed_snapshot_on FROM sys.databases WHERE database_id=DB_ID()
