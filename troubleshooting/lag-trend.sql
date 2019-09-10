declare @now datetime = GetUtcDate()

;with 
C as (select CheckpointNumber, CommitStamp,
		Timestamp = cast(substring(cast(Payload as varchar(max)), patindex('%"Timestamp":"%', cast(Payload as varchar(max)))+13, 19) as datetime)
	from Commits
)
select 
	[Hours Ago]=Value,
	CommitStamp,
	CheckpointNumber,
	Timestamp,
	[Days Lag] = cast(cast(CommitStamp as datetime) as float) - cast(Timestamp as float)
from Counter
cross apply(
	select top 1 CheckpointNumber, CommitStamp, Timestamp
	from C
	where CommitStamp < DATEADD(hour, -Value, @now)
	order by CheckpointNumber desc
) _
where Counter.Value<(24)
order by Value


