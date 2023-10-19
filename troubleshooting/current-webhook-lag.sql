;with M as (
	select Now=GETUTCDATE(), MaxSequence=cast(JSON_VALUE(Value, '$.MaxSequence') as int)
	from Config 
	where Instance='MatcherSubscription' and Type='CatchupSubscriptionManager'
),
ActivityStreamCommits as (
	select cast(CommitStamp as datetime) CommitStamp, CheckpointNumber, CommitSequence
	from Commits
	where BucketId = 'Meta' and StreamId = '1EE3982777943C1BD64B154C4B5008DC0C3815A0'
),
A as (select top 1 CommitStamp from ActivityStreamCommits order by CheckpointNumber desc),
B as (select CommitStamp, Now from ActivityStreamCommits join M on M.MaxSequence=CommitSequence)
select 
	Now,
	Latest=A.CommitStamp, 
	Processed=B.CommitStamp, 
	Behind_Min=CONVERT(FLOAT,A.CommitStamp - B.CommitStamp) * 24 * 60, --Decimal Minutes
	Lag_Min=CONVERT(FLOAT, Now - B.CommitStamp) * 24 * 60 --Decimal Minutes
from A,B