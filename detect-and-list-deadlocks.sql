/*
 *	Customer-facing SQL script template
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit;

declare @error int, @rowcount int
set nocount on; begin tran; save tran TX


SELECT Blocker.text, Blocker.*, *
FROM sys.dm_exec_connections AS Conns
INNER JOIN sys.dm_exec_requests AS BlockedReqs
    ON Conns.session_id = BlockedReqs.blocking_session_id
INNER JOIN sys.dm_os_waiting_tasks AS w
    ON BlockedReqs.session_id = w.session_id
CROSS APPLY sys.dm_exec_sql_text(Conns.most_recent_sql_handle) AS Blocker

/* after every modifying statement, check for errors; optionally, emit status */
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d foobars blah-blahed', 0, 1, @rowcount) with nowait


if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE: