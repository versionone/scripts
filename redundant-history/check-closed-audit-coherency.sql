set nocount on

declare @cnt int, @total int
select @total=0

select @cnt=count(*) from dbo.BaseAsset_Now where ClosedAuditID>AuditBegin
select @total=@total+@cnt
raiserror('%d BaseAsset_Now with a future closed audit', 0, 1, @cnt) with nowait

select @cnt=count(*) from dbo.BaseAsset_Now where ClosedAuditID is not null and AssetState<128
select @total=@total+@cnt
raiserror('%d open BaseAsset_Now with a closed audit', 0, 1, @cnt) with nowait

select @cnt=count(*) from dbo.BaseAsset_Now where ClosedAuditID is null and AssetState>=128 and AssetState<192
select @total=@total+@cnt
raiserror('%d closed BaseAsset_Now without a closed audit', 0, 1, @cnt) with nowait

select @cnt=count(*) from dbo.BaseAsset where ClosedAuditID is not null and AssetState<128
select @total=@total+@cnt
raiserror('%d open BaseAsset with a closed audit', 0, 1, @cnt) with nowait

select @cnt=count(*) from dbo.BaseAsset where ClosedAuditID is null and AssetState>=128 and AssetState<192
select @total=@total+@cnt
raiserror('%d closed BaseAsset without a closed audit', 0, 1, @cnt) with nowait

select @cnt=count(*)
from dbo.BaseAsset_Now ban
join dbo.BaseAsset ba on ba.ID=ban.ID and ba.AuditEnd is null
and ((ba.ClosedAuditID is null and ban.ClosedAuditID is not null) or (ba.ClosedAuditID is not null and ban.ClosedAuditID is null) or ba.ClosedAuditID<>ban.ClosedAuditID)
select @total=@total+@cnt
raiserror('%d closed audit mismatch between BaseAsset_Now and BaseAsset tip', 0, 1, @cnt) with nowait

select @cnt=count(*)
from dbo.BaseAsset ba
cross apply (select top 1 bac.* from BaseAsset bac where bac.ID=ba.ID and bac.AssetState=128 and bac.AuditBegin<=ba.AuditBegin and not exists (select * from BaseAsset bao where bao.ID=bac.ID and (bao.AssetState<128 or (bao.AssetState>=192 and bao.AssetState<255)) and bao.AuditBegin>bac.AuditBegin and bao.AuditBegin<ba.AuditBegin) order by AuditBegin) bac
where ba.AssetState>=128 and (ba.AssetState<192 or ba.AssetState=255) and (ba.ClosedAuditID is null or ba.ClosedAuditID<>bac.AuditBegin)
select @total=@total+@cnt
raiserror('%d closed audit mismatch between closed/deleted BasseAsset and its most recent closure', 0, 1, @cnt) with nowait

select @cnt=count(*)
from dbo.BaseAsset ba
outer apply (select top 1 bac.* from BaseAsset bac where bac.ID=ba.ID and bac.AssetState=128 and bac.AuditBegin<ba.AuditBegin and not exists (select * from BaseAsset bao where bao.ID=bac.ID and bao.AssetState<128 and bao.AuditBegin>bac.AuditBegin and bao.AuditBegin<ba.AuditBegin) order by AuditBegin) bac
where ba.AssetState>=192 and ba.ClosedAuditID is not null and bac.AuditBegin is null
select @total=@total+@cnt
raiserror('%d dead never closed BaseAsset with a closed audit', 0, 1, @cnt) with nowait

if @total>0 raiserror('%d incoherent closed audits detected', 16, 1, @total)
	