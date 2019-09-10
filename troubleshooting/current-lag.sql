
;with M as (
	select MaxAudit=cast(substring(Value, patindex('%"MaxAudit": %', Value)+12, patindex('%,%', Value)-patindex('%"MaxAudit": %', Value)-12) as int)
	from Config 
	where Instance='AuditSubscription' and Type='CatchupSubscriptionManager'
),
A as (select top 1 * from Audit order by ID desc),
B as (select Audit.* from Audit join M on M.MaxAudit=ID)
select 
	Latest=A.ChangeDateUTC, 
	Processed=B.ChangeDateUTC, 
	Behind=cast(A.ChangeDateUTC as float)-cast(B.ChangeDateUTC as float),
	Lag=cast(GETUTCDATE() as float)-cast(B.ChangeDateUTC as float)
from A,B

