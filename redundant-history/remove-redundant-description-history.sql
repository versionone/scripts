set nocount on
begin tran

alter table dbo.BaseAsset_Now disable trigger all

update dbo.BaseAsset
set Description=GoodID
from (
	select me.ID BadID, MIN(other.ID) GoodID
	from dbo.LongString me
	join dbo.LongString other on other.ID<me.ID and cast(other.Value as nvarchar(max))=cast(me.Value as nvarchar(max))
	group by me.ID
) Bad
where Description=BadID

update dbo.BaseAsset_Now
set Description=h.Description
from dbo.BaseAsset h
where h.ID=BaseAsset_Now.ID and h.AuditEnd is null and h.Description is not null and (h.Description<>BaseAsset_Now.Description or BaseAsset_Now.Description is null)

alter table dbo.BaseAsset_Now enable trigger all

--commit
rollback