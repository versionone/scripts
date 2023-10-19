declare @now datetime = getutcdate()
;with
C as (select CheckpointNumber, CommitStamp,
		Timestamp = cast(substring(cast(Payload as varchar(max)), patindex('%"Timestamp":"%', cast(Payload as varchar(max)))+13, 19) as datetime)
	from dbo.Commits
)
select [Hours Ago],[CommitStamp], [CheckpointNumber], [Timestamp], [Days Lag], [NewChanges],
[CheckpointNumber]-[PrevCheckpointNumber] as [ProcessedChanges]
from(
select
	[Hours Ago]=Value,
	CommitStamp,
	LEAD(CommitStamp) OVER (ORDER BY Value) as PrevCommitStamp,
	CheckpointNumber,
	LEAD(CheckpointNumber) OVER (ORDER BY Value) as PrevCheckpointNumber,
	Timestamp,
	[Days Lag] = cast(cast(CommitStamp as datetime) as float) - cast(Timestamp as float)
from dbo.Counter
cross apply(
	select top 1 CheckpointNumber, CommitStamp, Timestamp
	from C
	where CommitStamp < DATEADD(hour, -Value, @now)
	order by CheckpointNumber desc
) _
where Counter.Value<(48)
) __
cross apply(
	select count(1) as NewChanges
	from dbo.Audit
	where ChangeDateUTC between PrevCommitStamp and CommitStamp
) ___
order by [Hours Ago]