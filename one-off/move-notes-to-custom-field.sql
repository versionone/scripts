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

set nocount on
declare @assetID int, @auditBegin int, @author nvarchar(4000), @dateOf datetime, @title nvarchar(4000), @content nvarchar(max), @value nvarchar(max), @longtextID int, @sep char, @assetType varchar(100)


select @sep=','
create table #F(AssetType varchar(100), Definition varchar(100))
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


create table #T (ID int not null primary key, AuditBegin int not null, Value nvarchar(max))
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
	),
	Note as (
		select N.ID, AssetID, Name.Value Title, Content.Value Content
		from dbo.Note_Now N
		join dbo.String Name on Name.ID=Name
		join dbo.LongString Content on Content.ID=Content
		where PersonalToID is null and AssetState<128
	)
	select AssetID, AuditBegin, Author, DateOf, Title, Content
	from OriginalNote
	join Note on Note.ID=OriginalNote.ID
	order by OriginalNote.ID
open C
while 1=1 begin
	fetch next from C into @assetID, @auditBegin, @author, @dateOf, @title, @content
	if @@FETCH_STATUS<>0 break
	
	declare @header nvarchar(max)
	select @header = @title + ' (' + @author + ' on ' + convert(nvarchar(100), @dateOf, 107) + ')'
	
	declare @note nvarchar(max)
	select @note = '<h1>' + REPLACE(REPLACE(@header, '&', '&amp;'), '<', '&lt;') + '</h1>' + @content

	if not exists (select * from #T where ID=@assetID)
		insert #T select @assetID, @auditBegin, @note
	else
		update #T set Value=Value + @note where ID=@assetID
end
close C deallocate C
--select * from #T


begin tran; save tran TX
declare @error int, @rowcount varchar(20)


declare C cursor local fast_forward for
	select T.ID, T.AuditBegin, T.Value, B.AssetType
	from #T T
	join BaseAsset_Now B on B.ID=T.ID
	
open C
while 1=1 begin
	fetch next from C into @assetID, @auditBegin, @value, @assetType
	if @@FETCH_STATUS<>0 break
	
	exec _SaveLongString @value, @longtextID output
	
	insert dbo.CustomLongText 
	select Definition, @assetID, @auditBegin, null, @longtextID
	from #F
	where AssetType=@assetType
	
end
close C deallocate C

--select * from dbo.CustomLongText

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:

drop table #T
drop table #F
