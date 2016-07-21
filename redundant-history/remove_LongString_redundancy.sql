set nocount on
create table #results (tbl sysname not null, [rowcount] int not null)
GO

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
select me.ID BadID, _.ID GoodID
from dbo.LongString me
cross apply (
	select top 1 other.ID
	from dbo.LongString other
	where other.md5=me.md5 and other.ID<me.ID and cast(other.Value as nvarchar(max))=cast(me.Value as nvarchar(max))
	order by other.ID
) _
insert #results values('#Bad', @@ROWCOUNT)
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
insert #results values('BaseAsset.Description', @@ROWCOUNT)

alter table dbo.BaseAsset_Now disable trigger all
update dbo.BaseAsset_Now
set Description=h.Description
from dbo.BaseAsset h
where h.ID=BaseAsset_Now.ID and h.AuditEnd is null and h.Description is not null and (h.Description<>BaseAsset_Now.Description or BaseAsset_Now.Description is null)
insert #results values('BaseAsset_Now.Description', @@ROWCOUNT)
alter table dbo.BaseAsset_Now enable trigger all

update dbo.List
set Description=GoodID
from #Bad
where Description=BadID
insert #results values('List.Description', @@ROWCOUNT)

alter table dbo.List_Now disable trigger all
update dbo.List_Now
set Description=h.Description
from dbo.List h
where h.ID=List_Now.ID and h.AuditEnd is null and h.Description is not null and (h.Description<>List_Now.Description or List_Now.Description is null)
insert #results values('List_Now.Description', @@ROWCOUNT)
alter table dbo.List_Now enable trigger all

update dbo.Label
set Description=GoodID
from #Bad
where Description=BadID
insert #results values('Label.Description', @@ROWCOUNT)

alter table dbo.Label_Now disable trigger all
update dbo.Label_Now
set Description=h.Description
from dbo.Label h
where h.ID=Label_Now.ID and h.AuditEnd is null and h.Description is not null and (h.Description<>Label_Now.Description or Label_Now.Description is null)
insert #results values('Label_Now.Description', @@ROWCOUNT)
alter table dbo.Label_Now enable trigger all

update dbo.Attachment
set Description=GoodID
from #Bad
where Description=BadID
insert #results values('Attachment.Description', @@ROWCOUNT)

alter table dbo.Attachment_Now disable trigger all
update dbo.Attachment_Now
set Description=h.Description
from dbo.Attachment h
where h.ID=Attachment_Now.ID and h.AuditEnd is null and h.Description is not null and (h.Description<>Attachment_Now.Description or Attachment_Now.Description is null)
insert #results values('Attachment_Now.Description', @@ROWCOUNT)
alter table dbo.Attachment_Now enable trigger all

update dbo.Issue
set Resolution=GoodID
from #Bad
where Resolution=BadID
insert #results values('Issue.Resolution', @@ROWCOUNT)

alter table dbo.Issue_Now disable trigger all
update dbo.Issue_Now
set Resolution=h.Resolution
from dbo.Issue h
where h.ID=Issue_Now.ID and h.AuditEnd is null and h.Resolution is not null and (h.Resolution<>Issue_Now.Resolution or Issue_Now.Resolution is null)
insert #results values('Issue_Now.Resolution', @@ROWCOUNT)
alter table dbo.Issue_Now enable trigger all

update dbo.Request
set Resolution=GoodID
from #Bad
where Resolution=BadID
insert #results values('Request.Resolution', @@ROWCOUNT)

alter table dbo.Request_Now disable trigger all
update dbo.Request_Now
set Resolution=h.Resolution
from dbo.Request h
where h.ID=Request_Now.ID and h.AuditEnd is null and h.Resolution is not null and (h.Resolution<>Request_Now.Resolution or Request_Now.Resolution is null)
insert #results values('Request_Now.Resolution', @@ROWCOUNT)
alter table dbo.Request_Now enable trigger all

update dbo.Defect
set Resolution=GoodID
from #Bad
where Resolution=BadID
insert #results values('Defect.Resolution', @@ROWCOUNT)

alter table dbo.Defect_Now disable trigger all
update dbo.Defect_Now
set Resolution=h.Resolution
from dbo.Defect h
where h.ID=Defect_Now.ID and h.AuditEnd is null and h.Resolution is not null and (h.Resolution<>Defect_Now.Resolution or Defect_Now.Resolution is null)
insert #results values('Defect_Now.Resolution', @@ROWCOUNT)
alter table dbo.Defect_Now enable trigger all

update dbo.Test
set Setup=GoodID
from #Bad
where Setup=BadID
insert #results values('Test.Setup', @@ROWCOUNT)

alter table dbo.Test_Now disable trigger all
update dbo.Test_Now
set Setup=h.Setup
from dbo.Test h
where h.ID=Test_Now.ID and h.AuditEnd is null and h.Setup is not null and (h.Setup<>Test_Now.Setup or Test_Now.Setup is null)
insert #results values('Test_Now.Setup', @@ROWCOUNT)
alter table dbo.Test_Now enable trigger all

update dbo.Test
set Inputs=GoodID
from #Bad
where Inputs=BadID
insert #results values('Test.Inputs', @@ROWCOUNT)

alter table dbo.Test_Now disable trigger all
update dbo.Test_Now
set Inputs=h.Inputs
from dbo.Test h
where h.ID=Test_Now.ID and h.AuditEnd is null and h.Inputs is not null and (h.Inputs<>Test_Now.Inputs or Test_Now.Inputs is null)
insert #results values('Test_Now.Inputs', @@ROWCOUNT)
alter table dbo.Test_Now enable trigger all

update dbo.Test
set Steps=GoodID
from #Bad
where Steps=BadID
insert #results values('Test.Steps', @@ROWCOUNT)

alter table dbo.Test_Now disable trigger all
update dbo.Test_Now
set Steps=h.Steps
from dbo.Test h
where h.ID=Test_Now.ID and h.AuditEnd is null and h.Steps is not null and (h.Steps<>Test_Now.Steps or Test_Now.Steps is null)
insert #results values('Test_Now.Steps', @@ROWCOUNT)
alter table dbo.Test_Now enable trigger all

update dbo.Test
set ExpectedResults=GoodID
from #Bad
where ExpectedResults=BadID
insert #results values('Test.ExpectedResults', @@ROWCOUNT)

alter table dbo.Test_Now disable trigger all
update dbo.Test_Now
set ExpectedResults=h.ExpectedResults
from dbo.Test h
where h.ID=Test_Now.ID and h.AuditEnd is null and h.ExpectedResults is not null and (h.ExpectedResults<>Test_Now.ExpectedResults or Test_Now.ExpectedResults is null)
insert #results values('Test_Now.ExpectedResults', @@ROWCOUNT)
alter table dbo.Test_Now enable trigger all

update dbo.Test
set ActualResults=GoodID
from #Bad
where ActualResults=BadID
insert #results values('Test.ActualResults', @@ROWCOUNT)

alter table dbo.Test_Now disable trigger all
update dbo.Test_Now
set ActualResults=h.ActualResults
from dbo.Test h
where h.ID=Test_Now.ID and h.AuditEnd is null and h.ActualResults is not null and (h.ActualResults<>Test_Now.ActualResults or Test_Now.ActualResults is null)
insert #results values('Test_Now.ActualResults', @@ROWCOUNT)
alter table dbo.Test_Now enable trigger all

update dbo.Retrospective
set Summary=GoodID
from #Bad
where Summary=BadID
insert #results values('Retrospective.Summary', @@ROWCOUNT)

alter table dbo.Retrospective_Now disable trigger all
update dbo.Retrospective_Now
set Summary=h.Summary
from dbo.Retrospective h
where h.ID=Retrospective_Now.ID and h.AuditEnd is null and h.Summary is not null and (h.Summary<>Retrospective_Now.Summary or Retrospective_Now.Summary is null)
insert #results values('Retrospective_Now.Summary', @@ROWCOUNT)
alter table dbo.Retrospective_Now enable trigger all

update dbo.Subscription
set Description=GoodID
from #Bad
where Description=BadID
insert #results values('Subscription.Description', @@ROWCOUNT)

alter table dbo.Subscription_Now disable trigger all
update dbo.Subscription_Now
set Description=h.Description
from dbo.Subscription h
where h.ID=Subscription_Now.ID and h.AuditEnd is null and h.Description is not null and (h.Description<>Subscription_Now.Description or Subscription_Now.Description is null)
insert #results values('Subscription_Now.Description', @@ROWCOUNT)
alter table dbo.Subscription_Now enable trigger all

update dbo.RegressionTest
set Setup=GoodID
from #Bad
where Setup=BadID
insert #results values('RegressionTest.Setup', @@ROWCOUNT)

alter table dbo.RegressionTest_Now disable trigger all
update dbo.RegressionTest_Now
set Setup=h.Setup
from dbo.RegressionTest h
where h.ID=RegressionTest_Now.ID and h.AuditEnd is null and h.Setup is not null and (h.Setup<>RegressionTest_Now.Setup or RegressionTest_Now.Setup is null)
insert #results values('RegressionTest_Now.Setup', @@ROWCOUNT)
alter table dbo.RegressionTest_Now enable trigger all

update dbo.RegressionTest
set Inputs=GoodID
from #Bad
where Inputs=BadID
insert #results values('RegressionTest.Inputs', @@ROWCOUNT)

alter table dbo.RegressionTest_Now disable trigger all
update dbo.RegressionTest_Now
set Inputs=h.Inputs
from dbo.RegressionTest h
where h.ID=RegressionTest_Now.ID and h.AuditEnd is null and h.Inputs is not null and (h.Inputs<>RegressionTest_Now.Inputs or RegressionTest_Now.Inputs is null)
insert #results values('RegressionTest_Now.Inputs', @@ROWCOUNT)
alter table dbo.RegressionTest_Now enable trigger all

update dbo.RegressionTest
set Steps=GoodID
from #Bad
where Steps=BadID
insert #results values('RegressionTest.Steps', @@ROWCOUNT)

alter table dbo.RegressionTest_Now disable trigger all
update dbo.RegressionTest_Now
set Steps=h.Steps
from dbo.RegressionTest h
where h.ID=RegressionTest_Now.ID and h.AuditEnd is null and h.Steps is not null and (h.Steps<>RegressionTest_Now.Steps or RegressionTest_Now.Steps is null)
insert #results values('RegressionTest_Now.Steps', @@ROWCOUNT)
alter table dbo.RegressionTest_Now enable trigger all

update dbo.RegressionTest
set ExpectedResults=GoodID
from #Bad
where ExpectedResults=BadID
insert #results values('RegressionTest.ExpectedResults', @@ROWCOUNT)

alter table dbo.RegressionTest_Now disable trigger all
update dbo.RegressionTest_Now
set ExpectedResults=h.ExpectedResults
from dbo.RegressionTest h
where h.ID=RegressionTest_Now.ID and h.AuditEnd is null and h.ExpectedResults is not null and (h.ExpectedResults<>RegressionTest_Now.ExpectedResults or RegressionTest_Now.ExpectedResults is null)
insert #results values('RegressionTest_Now.ExpectedResults', @@ROWCOUNT)
alter table dbo.RegressionTest_Now enable trigger all

update dbo.CustomLongText
set Value=GoodID
from #Bad
where Value=BadID
insert #results values('CustomLongText.Value', @@ROWCOUNT)

update dbo.Room
set Description=GoodID
from #Bad
where Description=BadID
insert #results values('Room.Description', @@ROWCOUNT)

alter table dbo.Room_Now disable trigger all
update dbo.Room_Now
set Description=h.Description
from dbo.Room h
where h.ID=Room_Now.ID and h.AuditEnd is null and h.Description is not null and (h.Description<>Room_Now.Description or Room_Now.Description is null)
insert #results values('Room_Now.Description', @@ROWCOUNT)
alter table dbo.Room_Now enable trigger all

select * from #results

--commit
rollback
GO

drop table #Bad
GO

drop table #results
