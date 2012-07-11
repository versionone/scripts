select
        SUM(improvement_measure) improvement,
        [table], equality_columns, inequality_columns
from (
        select 
                migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS improvement_measure,
                DB_NAME(database_id) [database], OBJECT_NAME(object_id, database_id) [table],
                equality_columns, inequality_columns, included_columns,
                migs.*
        FROM sys.dm_db_missing_index_groups mig
        INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
        INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
        --order by 1 desc
) X
group by [table], equality_columns, inequality_columns
order by 1 desc

select
        SUM(improvement_measure) improvement,
        [table], equality_columns, inequality_columns, included_columns
from (
        select 
                migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS improvement_measure,
                DB_NAME(database_id) [database], OBJECT_NAME(object_id, database_id) [table],
                equality_columns, inequality_columns, included_columns,
                migs.*
        FROM sys.dm_db_missing_index_groups mig
        INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
        INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
        --order by 1 desc
) X
group by [table], equality_columns, inequality_columns, included_columns
order by 1 desc