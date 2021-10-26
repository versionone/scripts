/*	
 *	For cases when Taskboard shows non-stardard column widths per user.
 * 
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */

declare @saveChanges bit; --set @saveChanges = 1

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

if @saveChanges is null
	SELECT dbo.Profile_PathBinToStr([PATH]), [VALUE]
	  FROM dbo.[ProfileValue]
	  where [Value] like '%px' and dbo.Profile_PathBinToStr([PATH]) like '%/Gadgets/TeamRoom/TaskBoard/Widths/%'

else
	DELETE
	  FROM dbo.[ProfileValue]
	  where [Value] like '%px' and dbo.Profile_PathBinToStr([PATH]) like '%/Gadgets/TeamRoom/TaskBoard/Widths/%'


select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' AssetAudits' + iif(@saveChanges is null, ' to be deleted','deleted')


if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: