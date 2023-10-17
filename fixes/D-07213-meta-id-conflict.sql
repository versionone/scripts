/*	
 *	Fix Meta ID conflict, as identified in D-07213
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX


delete InsertUpdateRule_Now where ID=-6293
delete BaseRule_Now where ID=-6293

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' current business rules deleted'

delete InsertUpdateRule where ID=-6293
delete BaseRule where ID=-6293

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' historical business rules deleted'

if not OBJECT_ID('dbo.AssetAudit', 'U') is null
    delete AssetAudit where ID=-6293 and AssetType='BusinessRule'
else begin
    delete Asset_Now where ID=-6293 and AssetType='BusinessRule'
    delete Asset where ID=-6293 and AssetType='BusinessRule'
end

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' AssetAudits deleted'


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: