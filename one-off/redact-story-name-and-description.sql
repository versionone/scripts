declare @saveChanges bit; -- set @saveChanges=1
declare @storyNumber int=NNNNN

declare @storyId int
select @storyId=ID from dbo.Workitem_Now where AssetType='Story' and Number=@storyNumber

if (@storyId is null) begin
	raiserror('S-%d not found', 16, 1, @storyNumber)
	return
end
raiserror('Found Story:%d', 0, 1, @storyId) with nowait

declare @storyOid varchar(max)='Story:'+cast(@storyId as varchar(max))+':%'
declare @redacted nvarchar(max)=N'redacted'
declare @hash int=BINARY_CHECKSUM(@redacted)
declare @longHash binary(20)=cast(hashbytes('SHA2_512', @redacted) as binary(20))

set nocount on; begin tran; save tran tx
declare @error int, @rowcount int

update dbo.String
set Value=@redacted, Hash=@hash
from dbo.BaseAsset
where String.ID=Name and BaseAsset.ID=storyId

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d Names redacted', 0, 1, @rowcount) with nowait

update dbo.LongString
set Value=@redacted, Hash=@longHash
from dbo.BaseAsset
where LongString.ID=Description and BaseAsset.ID=@storyId

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d Descriptions redacted', 0, 1, @rowcount) with nowait

delete dbo.Commits
where cast(Payload as varchar(max)) like '%Asset":"'+@storyOid and (
	cast(Payload as varchar(max)) like '%"Name":"Name"%' or
	cast(Payload as varchar(max)) like '%"Name":"Description"%'
)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d Commits deleted', 0, 1, @rowcount) with nowait

delete dbo.WebhookEvents
where cast(Payload as varchar(max)) like '%oid":"'+@storyOid and (
	cast(Payload as varchar(max)) like '%"name":"Name"%' or
	cast(Payload as varchar(max)) like '%"name":"Description"%'
)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d WebhookEvents deleted', 0, 1, @rowcount) with nowait

if @saveChanges=1 goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1', 16, 1)
ERR: rollback tran tx
OK: commit
