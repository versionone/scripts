; with query_info as (
	select query_hash
		, query_sql = text
		, query_plan
		, statement = substring(text, (statement_start_offset/2) + 1, ((case statement_end_offset 	when -1 then datalength(text) else statement_end_offset end - statement_start_offset)/2) + 1)
	from sys.dm_exec_query_stats
	cross apply sys.dm_exec_sql_text(sql_handle)
	cross apply sys.dm_exec_query_plan(plan_handle)
), query_stats as (
	select top 10 query_hash
		, sum(execution_count) total_execution_count

		, round(convert(float,sum(total_worker_time))/1000000.0, 0) total_cpu_sec
		, round(convert(float,sum(total_elapsed_time))/1000000.0, 0) total_duration_sec
		, sum(total_physical_reads) total_physical_reads
		, sum(total_logical_reads) total_logical_reads
		, sum(total_logical_writes) total_logical_writes

		, round (convert (float, sum(total_worker_time)) / convert (float, sum(execution_count)) / 1000000.0, 4) as avg_cpu_sec
		, round (convert (float, sum(total_elapsed_time)) / convert (float, sum(execution_count)) / 1000000.0, 4) as avg_duration_sec
		, sum(total_physical_reads) / sum(execution_count) as avg_physical_reads
		, sum(total_logical_reads)  / sum(execution_count) as avg_logical_reads
		, sum(total_logical_writes) / sum(execution_count) as avg_logical_writes
		, convert(float,sum(total_elapsed_time))/convert(float,sum(total_worker_time)) waiting_ratio
	from sys.dm_exec_query_stats
	group by query_hash
	having sum(execution_count)>10 and convert(float,sum(total_worker_time))/1000000.0>1 and convert(float,sum(total_elapsed_time))/1000000.0>2
	--order by 2 desc --Executions
	--order by 3 desc --CPU
	--order by 4 desc --Duration
	--order by 5 desc --Physical Reads    
	--order by 6 desc --Reads 
	--order by 7 desc --Writes
	--order by 8 desc --Avg CPU
	order by 9 desc --Avg Duration     
	--order by 10 desc --Avg PhysicalReads
	--order by 11 desc --Avg Reads
	--order by 12 desc --Avg Writes
	--order by 13 desc --Waiting Ratio
)
select stats.*, query_sql sample_query_sql, query_plan sample_query_plan, statement
	from query_stats stats
	cross apply (
		select top 1 *
		from query_info
		where query_info.query_hash=stats.query_hash
	) info
