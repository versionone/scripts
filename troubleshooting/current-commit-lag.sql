;with stamps as (
	select top 1 cast(json_value(stuff(cast(Payload as varchar(max)), 1, 3, ''), '$[0].Body.Timestamp') as datetime) AuditStamp, cast(CommitStamp as datetime) CommitStamp
	from dbo.Commits
	order by CheckpointNumber desc
)
select
Latest = AuditStamp,
Processed = CommitStamp,
Behind = CONVERT(FLOAT,CommitStamp-AuditStamp) * 24 * 60, --Decimal Minutes
Lag = CONVERT(FLOAT,getdate()-CommitStamp) * 24 * 60 --Decimal Minutes
from stamps