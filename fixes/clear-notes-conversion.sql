/*	
 *	Clears all Expressions that were converted from Notes.
 *	This will cause Notes to be re-converted on the next upgrade.
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @supportedVersions varchar(1000); select @supportedVersions='10.3.*, 11.*'

BEGIN
	declare @sep char(2); select @sep=', '
	if not exists(select *
		from dbo.SystemConfig
		join (
		select SUBSTRING(@supportedVersions, C.Value+1, CHARINDEX(@sep, @supportedVersions+@sep, C.Value+1)-C.Value-1) as Value
		from dbo.Counter C
		where C.Value < DataLength(@supportedVersions) and SUBSTRING(@sep+@supportedVersions, C.Value+1, DataLength(@sep)) = @sep
		) Version on SystemConfig.Value like REPLACE(Version.Value, '*', '%') and SystemConfig.Name = 'Version'
	) begin
			raiserror('Only supported on version(s) %s',16,1, @supportedVersions)
			goto DONE
	end
END

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

delete dbo.ExpressionBaseAssets
from Note_Now 
where Note_Now.ID=ExpressionBaseAssets.ExpressionID

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' ExpressionBaseAssets deleted'

delete dbo.ExpressionMentions
from Note_Now 
where Note_Now.ID=ExpressionMentions.ExpressionID

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' ExpressionMentions deleted'

delete dbo.Expression_Now
from Note_Now 
where Note_Now.ID=Expression_Now.ID

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' Expression_Now deleted'

delete dbo.Expression
from Note_Now 
where Note_Now.ID=Expression.ID

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' Expression (history) deleted'

update dbo.Note_Now set Conversion=0
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' Notes marked unconverted'

update dbo.Note set Conversion=0
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' Notes (history) marked unconverted'

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: