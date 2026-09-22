/*
This script redacts a specific tag associated with a specific workitem.
Set @workitemNumber to the number of the workitem you want to redact.
Set @assetType to the type of the workitem (e.g., 'Story').
Set @tagValue to the exact tag value to redact.
Set @replaceWith to the value that will replace the tag.
Set @saveChanges to 1 to commit changes, or 0 to roll back.
*/

declare @workitemNumber int=NNNNN
declare @assetType varchar(100)=NULL -- e.g. 'Story'
declare @tagValue nvarchar(440)=NULL -- e.g. 'item for review' (the literal tag value)
declare @replaceWith nvarchar(440)='redacted'
declare @saveChanges bit; --set @saveChanges = 1

declare @workitemId int
select @workitemId=ID from dbo.Workitem_Now where AssetType=@assetType and Number=@workitemNumber

if (@workitemId is null) begin
	raiserror('%d not found', 16, 1, @workitemNumber)
	return
end
raiserror('Found %s:%d', 0, 1, @assetType, @workitemId) with nowait

if exists (
	select 1
	from dbo.BaseAssetTaggedWith
	where ID=@workitemId
	and Value=@replaceWith
	and Value<>@tagValue
) begin
	raiserror('Replacement tag already exists in this workitem''s history', 16, 1)
	return
end

declare @workitemOid varchar(max)=@assetType+':'+cast(@workitemId as varchar(max))+':%'

set nocount on; begin tran; save tran tx
declare @error int, @rowcount int

update dbo.BaseAssetTaggedWith
set Value=@replaceWith
where ID=@workitemId and Value=@tagValue

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d Tags deleted', 0, 1, @rowcount) with nowait

declare @encodedTag as nvarchar (max) = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@tagValue, N'\', N'\\'), N'"', N'\"'), N'~', N'~~'), N'%', N'~%'), N'_', N'~_'), N'[', N'~[');

delete dbo.Commits
where cast(Payload as varchar(max)) like '%Asset":"'+@workitemOid 
and cast(Payload as varchar(max)) like '%"Name":"TaggedWith"%Value":"'+@encodedTag+'"%' ESCAPE N'~';


select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d Commits deleted', 0, 1, @rowcount) with nowait

delete dbo.WebhookEvents
where cast(Payload as varchar(max)) like '%oid":"'+@workitemOid 
and cast(Payload as varchar(max)) like '%"name":"TaggedWith"%"new":"'+@encodedTag+'"%' ESCAPE N'~';

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d WebhookEvents deleted', 0, 1, @rowcount) with nowait

if @saveChanges=1 goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1', 16, 1)
ERR: rollback tran tx
OK: commit