/*	
 *	Scramble all text in a VersionOne database.
 *	
 *	It MUST only be run on a COPY of a production database, not on the real one.
 *	When committed, the changes are irreversible.
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1

exec('
	create view dbo.__RandomNumberView
	as
		select RAND() as rnd
')

exec('
	create function dbo.__RandomNumber ()
	returns float
	as
	begin
		return (select rnd from dbo.__RandomNumberView)
	end
')

exec('
	create function dbo.__RandomChar (@c char(1)) returns char(1)
	begin
		declare @a int, @uchars char(26), @lchars char(26), @nchars char(10)
		select @a = ASCII(@c), @uchars = ''ABCDEFGHIJKLMNOPQRSTUVWXYZ'', @lchars = ''abcdefghijklmnopqrstuvwxyz'', @nchars = ''0123456789''
		if (@a >= 65 and @a <= 90)
			return SUBSTRING(@uchars, cast(dbo.__RandomNumber() * LEN(@uchars) + 1 as int), 1)
		if (@a >= 97 and @a <= 122)
			return SUBSTRING(@lchars, cast(dbo.__RandomNumber() * LEN(@lchars) + 1 as int), 1)
		if (@a >= 48 and @a <= 57)
			return SUBSTRING(@nchars, cast(dbo.__RandomNumber() * LEN(@nchars) + 1 as int), 1)
		return @c
	end
')

exec('
	create function dbo.__RandomString (@s varchar(4000)) returns varchar(4000)
	begin
		declare @o varchar(4000); select @o = ''''
		select @o = @o + dbo.__RandomChar(SUBSTRING(@s, C.Value+1, 1))
		from dbo.Counter C
		where C.Value < LEN(@s)
		return @o
	end
')

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

update dbo.String set Value=dbo.__RandomString(Value)
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' strings scrambled'

if exists (select * from INFORMATION_SCHEMA.TABLES where TABLE_SCHEMA='dbo' and TABLE_NAME='BaseAssetTaggedWith' and TABLE_TYPE='BASE TABLE') begin
	update dbo.BaseAssetTaggedWith set Value=dbo.__RandomString(Value)
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	print @rowcount + ' tags scrambled'
end

update dbo.LongString set Value='This Is a Random Description ' + cast(NEWID() as varchar(100))
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' descriptions scrambled'

update dbo.Blob set Value=0x
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' blobs truncated'

if exists (select * from INFORMATION_SCHEMA.ROUTINES where ROUTINE_SCHEMA='dbo' and ROUTINE_NAME='Thumbprint' and ROUTINE_TYPE='FUNCTION') begin
	print 'drop function dbo.Thumbprint'
	drop function dbo.Thumbprint
end

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:

drop function dbo.__RandomString 
drop function dbo.__RandomChar
drop function dbo.__RandomNumber 
drop view dbo.__RandomNumberView 
