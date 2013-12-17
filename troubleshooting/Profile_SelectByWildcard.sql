drop proc dbo.Profile_SelectByWildcard
GO
create proc dbo.Profile_SelectByWildcard (
	@pattern varchar(8000)
) as

declare @sep char(1);select @sep='/'

declare C cursor for
	select PN.ID, substring(@pattern, SlashIndex+1, NextSlashIndex-SlashIndex-1) Name
	from (
		select C.Value SlashIndex, charindex(@sep,@pattern+@sep,C.Value+1) NextSlashIndex
		from Counter C
		where substring(@pattern+@sep,C.Value,1)=@sep and C.Value<= len(@pattern)
	) X
	left join ProfileName PN on PN.Name=substring(@pattern, SlashIndex+1, NextSlashIndex-SlashIndex-1)
	
declare @id int, @name varchar(100)
declare @index int; select @index = -1
declare @joinClause varchar(8000), @whereClause varchar(8000)
select @joinClause = '', @whereClause = ''
declare @matchBase varchar(100), @matchOffset int, @match varbinary(8000)
select @matchBase = null, @matchOffset = 0, @match = 0x
declare @matchAt varchar(100), @whereCondition varchar(1000), @join varchar(1000), @counter varchar(100), @counterValue varchar(100)

open C
while 1=1 begin
	fetch next from C into @id, @name
	if @@FETCH_STATUS<>0 break
	
	select @index = @index + 1
	--select @index, @id, @name
	
	if (@id is null and @name<>'*' and @name<>'**') begin
		select @joinClause = '', @whereClause = char(10) + 'where 1=2', @match = 0x
		break
	end

	if (@id is not null and @name<>'*' and @name<>'**') begin
		select @match = @match + cast(@id as binary(4))
		continue
	end
	
	if (datalength(@match) > 0) begin
		if (@join is not null)
			select @joinClause = @joinClause + char(10) + @join, @join = null
		select @matchAt = case 
			when @matchBase is null then cast(@matchOffset as varchar(100)) 
			when @matchOffset>0 then '(' + @matchBase + '+' + cast(@matchOffset as varchar(100)) + ')'
			else @matchBase 
		end
		if (@matchAt = '0')
			select @whereCondition = dbo.HexString(@match) + '<=Path and Path<' + dbo.HexString(dbo.Profile_PathUpperBound(@match))
		else
			select @whereCondition = 'substring(Path,' + @matchAt + '*4+1,' + cast(datalength(@match) as varchar(100)) + ')=' + dbo.HexString(@match)
		select @whereClause = @whereClause + char(10) + case when @whereClause='' then 'where ' else char(9) + 'and ' end + @whereCondition, @matchOffset = @matchOffset + datalength(@match)/4, @match = 0x
	end
	
	if (@name = '*') begin
		select @matchOffset = @matchOffset + 1
	end
	
	else if (@name = '**') and (@join is null) begin
		select @counter = 'C' + cast(@index as varchar(100))
		select @counterValue = @counter + '.Value'
		select @matchAt = case 
			when @matchBase is null then cast(@matchOffset as varchar(100)) 
			when @matchOffset>0 then '(' + @matchBase + '+' + cast(@matchOffset as varchar(100)) + ')'
			else @matchBase 
		end
		select @join = 'join Counter ' + @counter + ' on ' + @matchAt + '<=' + @counterValue + ' and ' + @counterValue + '<=datalength(Path)/4'
		select @matchBase = @counterValue, @matchOffset = 0
	end
	
end
close C; deallocate C

if (datalength(@match) > 0) begin
	if (@join is not null)
		select @joinClause = @joinClause + char(10) + @join, @join = null
	select @matchAt = case 
		when @matchBase is null then cast(@matchOffset as varchar(100)) 
		when @matchOffset>0 then '(' + @matchBase + '+' + cast(@matchOffset as varchar(100)) + ')'
		else @matchBase 
	end
	select @whereCondition = 'substring(Path,' + @matchAt + '*4+1,' + cast(datalength(@match) as varchar(100)) + ')=' + dbo.HexString(@match)
	select @whereClause = @whereClause + char(10) + case when @whereClause='' then 'where ' else char(9) + 'and ' end + @whereCondition, @matchOffset = @matchOffset + datalength(@match)/4, @match = 0x
end

declare @sql varchar(8000)
select @sql = 'select dbo.Profile_PathBinToStr(PV.Path) Path, PV.Value from dbo.ProfileValue PV' + @joinClause + @whereClause + char(10) + 'order by 1'

print @sql
exec(@sql)

GO
