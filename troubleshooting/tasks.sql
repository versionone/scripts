SELECT  [w].[session_id],
        [w].[wait_duration_ms],
        [w].[wait_type],
        [w].[resource_description],
          [t].[text],
          [p].[query_plan]
FROM    [sys].[dm_os_waiting_tasks] AS [w]
INNER JOIN [sys].[dm_exec_requests] AS [r]
        ON [w].[session_id] = [r].[session_id]
INNER JOIN [sys].[dm_exec_sessions] AS [s]
        ON [s].[session_id] = [r].[session_id]
CROSS APPLY [sys].[dm_exec_sql_text]([r].[sql_handle]) AS [t]
CROSS APPLY [sys].[dm_exec_query_plan]([r].[plan_handle]) AS [p]
WHERE   [s].[is_user_process] = 1;
