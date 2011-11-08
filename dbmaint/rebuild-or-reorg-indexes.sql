set nocount on

DECLARE @objectid int;
DECLARE @indexid int;
DECLARE @partitioncount bigint;
DECLARE @schemaname sysname;
DECLARE @objectname sysname;
DECLARE @indexname sysname;
DECLARE @partitionnum bigint;
DECLARE @partitions bigint;
DECLARE @frag float;
DECLARE @command varchar(8000) ;

DECLARE partitions CURSOR FOR
SELECT object_id AS objectid, index_id AS indexid, partition_number AS partitionnum, avg_fragmentation_in_percent AS frag
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED')
WHERE avg_fragmentation_in_percent > 10.0
    AND
    index_id > 0
    and
    page_count > 50;

OPEN partitions;
FETCH NEXT
FROM partitions
INTO @objectid, @indexid, @partitionnum, @frag;

WHILE @@FETCH_STATUS = 0
BEGIN;
    SELECT @objectname = o.name, @schemaname = s.name
    FROM ..sys.objects AS o
    JOIN ..sys.schemas as s ON s.schema_id = o.schema_id
    WHERE o.object_id = @objectid;
    
    SELECT @indexname = name
    FROM ..sys.indexes
    WHERE object_id = @objectid
        AND
        index_id = @indexid;
    
    SELECT @partitioncount = count (*)
    FROM ..sys.partitions
    WHERE object_id = @objectid
        AND
        index_id = @indexid;
    
    PRINT '-- ' + @schemaname + '.' + @objectname + '.' + @indexname + ' is ' + CAST(ROUND(@frag,2) as nvarchar(10)) + '% fragmented'
    IF @frag < 25.0
    BEGIN;
        SELECT @command = 'ALTER INDEX ' + @indexname + ' ON .' + @schemaname + '.' + @objectname + ' REORGANIZE';
        PRINT(@command) ;
    END;
    IF @frag >= 25.0
    BEGIN;
        SELECT @command = 'ALTER INDEX ' + @indexname + ' ON .' + @schemaname + '.' + @objectname + ' REBUILD WITH (PAD_INDEX = ON, FILLFACTOR = 95)';
        PRINT(@command) ;
    END;
    SELECT @command = 'UPDATE STATISTICS .' + @schemaname + '.' + @objectname + ' ' + @indexname;
    PRINT(@command) ;
    FETCH NEXT
    FROM partitions
    INTO @objectid, @indexid, @partitionnum, @frag;

END;
CLOSE partitions;
DEALLOCATE partitions;
