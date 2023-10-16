;with stamps as (
	select top 1 cast(json_value(stuff(cast(Payload as varchar(max)), 1, 3, ''), '$[0].Body.Timestamp') as datetime) AuditStamp, cast(CommitStamp as datetime) CommitStamp
	from dbo.Commits
	order by CheckpointNumber desc
),
A as (select top 1 * from dbo.Audit order by ID desc)
select
Ocurred = AuditStamp,
Processed = CommitStamp,
CycleTime_Min = CONVERT(FLOAT,CommitStamp - AuditStamp) * 24 * 60, --Decimal Minutes
Behind_Min = CONVERT(FLOAT,A.ChangeDateUTC - AuditStamp) * 24 * 60, --Decimal Minutes
Lag_Min = CONVERT(FLOAT,getutcdate()-CommitStamp) * 24 * 60 --Decimal Minutes
from stamps, A