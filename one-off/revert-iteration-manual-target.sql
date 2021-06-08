/*	
 *	Reset config value manualTarget2 to working key (manualTarget)
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @error int, @rowcount int, @remaining int
set nocount on; begin tran; save tran TX
create table #ids(Instance varchar(100) not null, Type varchar(100) not null)
INSERT #ids(Instance, Type)
select Instance, Type
FROM dbo.Config
WHERE Value like '%manualTarget2%'
UPDATE conf
SET Value=JSON_MODIFY(
  JSON_MODIFY(Value,'$.manualTarget', CAST(JSON_VALUE(Value,'$.manualTarget2') AS varchar)),
  '$.manualTarget2',
  NULL
 )
FROM #ids
INNER JOIN dbo.[Config] conf ON 
#ids.Instance COLLATE Latin1_General_BIN = conf.Instance COLLATE Latin1_General_BIN
AND 
#ids.Type COLLATE Latin1_General_BIN = conf.Type COLLATE Latin1_General_BIN 
/* after every modifying statement, check for errors; optionally, emit status */
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d configurations updated', 0, 1, @rowcount) with nowait
SELECT @remaining = COUNT(*)
FROM dbo.[Config]
WHERE Value like '%manualTarget2%'
raiserror('%d remaining configurations', 0, 1, @remaining) with nowait
DROP TABLE #ids
if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit


