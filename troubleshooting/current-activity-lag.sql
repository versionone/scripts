;with M as (
	select MaxSequence=convert(int, ltrim(rtrim(substring(Value, patindex('%"MaxSequence":%', Value)+14, patindex('%'+CHAR(13)+char(10)+'}%', Value)-patindex('%"MaxSequence": %', Value)-14))))
	from Config 
	where Instance='MetaStreamSubscription' and Type='CatchupSubscriptionManager'
),
A as (select top 1 * from Commits order by CommitSequence desc),
B as (select Commits.* from Commits join M on M.MaxSequence=CommitSequence)
select 
	Latest=A.CommitStamp, 
	Processed=B.CommitStamp, 
	Behind_Sec=DATEDIFF(s, B.CommitStamp, A.CommitStamp),
	Lag_Sec=DATEDIFF(s, B.CommitStamp, GETUTCDATE())
from A,B