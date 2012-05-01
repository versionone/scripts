alter table dbo.LongString add md5 binary(16) null
GO

update dbo.LongString set md5=sys.fn_repl_hash_binary(cast(cast(Value as nvarchar(max)) as varbinary(max)))
GO

alter table dbo.LongString alter column md5 binary(16) not null
GO

create index ix_md5_id on dbo.LongString(md5, ID)
GO

create table #Bad (BadID int not null primary key, GoodID int not null)

insert #Bad(BadID, GoodID)
select BadID, GoodID from (
	select me.ID BadID, MIN(other.ID) GoodID
	from dbo.LongString me
	join dbo.LongString other on other.ID<me.ID and other.md5=me.md5
	group by me.ID
) _
join dbo.LongString bad on bad.ID=BadID
join dbo.LongString good on good.ID=GoodID
where cast(good.Value as nvarchar(max))=cast(bad.Value as nvarchar(max))
GO

drop index ix_md5_id on dbo.LongString
GO

alter table dbo.LongString drop column md5
GO

begin tran

update dbo.BaseAsset
set Description=GoodID
from #Bad
where Description=BadID

alter table dbo.BaseAsset_Now disable trigger all
update dbo.BaseAsset_Now
set Description=h.Description
from dbo.BaseAsset h
where h.ID=BaseAsset_Now.ID and h.AuditEnd is null and h.Description is not null and (h.Description<>BaseAsset_Now.Description or BaseAsset_Now.Description is null)
alter table dbo.BaseAsset_Now enable trigger all

update dbo.List
set Description=GoodID
from #Bad
where Description=BadID

alter table dbo.List_Now disable trigger all
update dbo.List_Now
set Description=h.Description
from dbo.List h
where h.ID=List_Now.ID and h.AuditEnd is null and h.Description is not null and (h.Description<>List_Now.Description or List_Now.Description is null)
alter table dbo.List_Now enable trigger all

update dbo.Label
set Description=GoodID
from #Bad
where Description=BadID

alter table dbo.Label_Now disable trigger all
update dbo.Label_Now
set Description=h.Description
from dbo.Label h
where h.ID=Label_Now.ID and h.AuditEnd is null and h.Description is not null and (h.Description<>Label_Now.Description or Label_Now.Description is null)
alter table dbo.Label_Now enable trigger all

update dbo.Attachment
set Description=GoodID
from #Bad
where Description=BadID

alter table dbo.Attachment_Now disable trigger all
update dbo.Attachment_Now
set Description=h.Description
from dbo.Attachment h
where h.ID=Attachment_Now.ID and h.AuditEnd is null and h.Description is not null and (h.Description<>Attachment_Now.Description or Attachment_Now.Description is null)
alter table dbo.Attachment_Now enable trigger all

update dbo.Issue
set Resolution=GoodID
from #Bad
where Resolution=BadID

alter table dbo.Issue_Now disable trigger all
update dbo.Issue_Now
set Resolution=h.Resolution
from dbo.Issue h
where h.ID=Issue_Now.ID and h.AuditEnd is null and h.Resolution is not null and (h.Resolution<>Issue_Now.Resolution or Issue_Now.Resolution is null)
alter table dbo.Issue_Now enable trigger all

update dbo.Request
set Resolution=GoodID
from #Bad
where Resolution=BadID

alter table dbo.Request_Now disable trigger all
update dbo.Request_Now
set Resolution=h.Resolution
from dbo.Request h
where h.ID=Request_Now.ID and h.AuditEnd is null and h.Resolution is not null and (h.Resolution<>Request_Now.Resolution or Request_Now.Resolution is null)
alter table dbo.Request_Now enable trigger all

update dbo.Defect
set Resolution=GoodID
from #Bad
where Resolution=BadID

alter table dbo.Defect_Now disable trigger all
update dbo.Defect_Now
set Resolution=h.Resolution
from dbo.Defect h
where h.ID=Defect_Now.ID and h.AuditEnd is null and h.Resolution is not null and (h.Resolution<>Defect_Now.Resolution or Defect_Now.Resolution is null)
alter table dbo.Defect_Now enable trigger all

update dbo.Retrospective
set Summary=GoodID
from #Bad
where Summary=BadID

alter table dbo.Retrospective_Now disable trigger all
update dbo.Retrospective_Now
set Summary=h.Summary
from dbo.Retrospective h
where h.ID=Retrospective_Now.ID and h.AuditEnd is null and h.Summary is not null and (h.Summary<>Retrospective_Now.Summary or Retrospective_Now.Summary is null)
alter table dbo.Retrospective_Now enable trigger all

update dbo.Subscription
set Description=GoodID
from #Bad
where Description=BadID

alter table dbo.Subscription_Now disable trigger all
update dbo.Subscription_Now
set Description=h.Description
from dbo.Subscription h
where h.ID=Subscription_Now.ID and h.AuditEnd is null and h.Description is not null and (h.Description<>Subscription_Now.Description or Subscription_Now.Description is null)
alter table dbo.Subscription_Now enable trigger all

update dbo.CustomLongText
set Value=GoodID
from #Bad
where Value=BadID

commit
GO

drop table #Bad
GO
