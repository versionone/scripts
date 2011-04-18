/*	
 *	Move Notes into a custom rich-text field.
 *	
 *	Set the @fields variable to a comma-delimited list of custom fields to populate.
 *	
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @fields varchar(4000); set @fields = 'PrimaryWorkitem.Custom_Notes,Scope.Custom_Whatever,Timebox.Custom_Blah'
collate Latin1_General_BIN

set nocount on
declare @assetID int, @auditBegin int, @author nvarchar(4000), @dateOf datetime, @title nvarchar(4000), @content nvarchar(max), @value nvarchar(max), @longtextID int, @sep char, @assetType varchar(100)


select @sep=','
create table #F(AssetType varchar(100) collate Latin1_General_BIN, Definition varchar(100) collate Latin1_General_BIN)
insert #F
select Y.AssetType, X.Definition
from (
	select Definition, LEFT(Definition, CHARINDEX('.', Definition)-1) AssetType
	from (
		select SUBSTRING(@sep+@fields+@sep, C.Value, CHARINDEX(@sep, @sep+@fields+@sep, C.Value)-C.Value) as Definition
		from dbo.Counter C
		where C.Value <= LEN(@sep+@fields+@sep) and SUBSTRING(@sep+@fields+@sep, C.Value-1, 1) = @sep
	) X
) X
join (
	select A.Name AssetType, B.Name BaseType
	from dbo.AssetTypeBaseHierarchy H
	join dbo.AssetType_Now A on H.DescendantID=A.ID
	join dbo.AssetType_Now B on H.AncestorID=B.ID
	where AuditEnd is null
) Y on Y.BaseType=X.AssetType

--select * from #F


create table #N (ID int not null primary key, AssetID int not null, AssetType varchar(100) collate Latin1_General_BIN, Title nvarchar(max), Content nvarchar(max))
insert #N
	select N.ID, B.ID, B.AssetType, Name.Value, Content.Value
	from dbo.Note_Now N
	join dbo.BaseAsset_Now B on B.ID=N.AssetID
	join dbo.String Name on Name.ID=N.Name
	join dbo.LongString Content on Content.ID=N.Content
	where N.PersonalToID is null and N.AssetState<128
		and B.AssetType in (select AssetType from #F)

--select * from #N


create table #T (ID int not null primary key, AssetType varchar(100) collate Latin1_General_BIN, AuditBegin int not null, Value nvarchar(max))
declare C cursor local fast_forward for
	with Author as (
		select M.ID, Name.Value Name
		from dbo.BaseAsset_Now M
		join String Name on Name.ID=Name
		where M.AssetType='Member'
	),
	OriginalNote as (
			select N.ID, Author.Name Author, ChangeDateUTC DateOf, AuditBegin
			from (
				select ID, AuditBegin, ROW_NUMBER() over (partition by ID order by AuditBegin) rownum
				from dbo.Note
			) N 
			join Audit on Audit.ID=AuditBegin
			join Author on Author.ID=Audit.ChangedByID
			where rownum=1
	)
	select AssetID, AssetType, AuditBegin, Author, DateOf, Title, Content
	from OriginalNote
	join #N Note on Note.ID=OriginalNote.ID
	order by OriginalNote.ID
open C
while 1=1 begin
	fetch next from C into @assetID, @assetType, @auditBegin, @author, @dateOf, @title, @content
	if @@FETCH_STATUS<>0 break
	
	declare @header nvarchar(max)
	select @header = @title + ' (' + @author + ' on ' + convert(nvarchar(100), @dateOf, 107) + ')'
	
	declare @note nvarchar(max)
	select @note = '<h1>' + REPLACE(REPLACE(@header, '&', '&amp;'), '<', '&lt;') + '</h1>' + @content

	if not exists (select * from #T where ID=@assetID)
		insert #T values(@assetID, @assetType, @auditBegin, @note)
	else
		update #T set Value=Value + @note where ID=@assetID
end
close C deallocate C
--select * from #T


if exists (
	select * 
	from #T T
	join #F F on T.AssetType=F.AssetType
	join dbo.CustomLongText C on C.ID=T.ID and C.Definition=F.Definition and C.AuditEnd is null
) begin
	raiserror('Existing custom field values would be overwritten',16,1)
	goto DONE
end


begin tran; save tran TX
declare @error int, @rowcount int, @rowtotal int; select @error=0, @rowtotal=0


declare C cursor local fast_forward for
	select T.ID, T.AssetType, T.AuditBegin, T.Value
	from #T T
	
open C
while 1=1 begin
	fetch next from C into @assetID, @assetType, @auditBegin, @value
	if @@FETCH_STATUS<>0 break
	
	exec _SaveLongString @value, @longtextID output
	
	insert dbo.CustomLongText 
	select Definition, @assetID, @auditBegin, null, @longtextID
	from #F
	where AssetType=@assetType

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 break
	select @rowtotal = @rowtotal + @rowcount
end
close C deallocate C
if @error<>0 goto ERR
print cast(@rowtotal as varchar(20)) + ' Note threads converted'

--select * from dbo.CustomLongText

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:

drop table #T
drop table #N
drop table #F
