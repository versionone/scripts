
-- Quick capture of session, host, login, sql text, blocking text
-- reads, writes, cpu, and writes in tempdb
SELECT  [r].[session_id],
        [s].[host_name],
        [s].[login_name],
        [r].[start_time],
        [r].[sql_handle],
		[st].[text],
        [r].[wait_type],
        [r].[blocking_session_id],
        [r].[reads],
        [r].[writes],
        [r].[cpu_time],
        [t].[user_objects_alloc_page_count],
        [t].[internal_objects_alloc_page_count]
FROM    [sys].[dm_exec_requests] AS [r]
JOIN    [sys].[dm_exec_sessions] AS [s]
        ON [s].[session_id] = [r].[session_id]
JOIN    [sys].[dm_db_task_space_usage] AS [t]
        ON [s].[session_id] = [t].[session_id] AND
           [r].[request_id] = [t].[request_id]
CROSS APPLY [sys].[dm_exec_sql_text](r.[sql_handle]) AS [st]
WHERE   [r].[status] IN ('running', 'runnable', 'suspended');
GO

