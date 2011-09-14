set nocount on

declare @totalCount real, @redundantCount real
select @totalCount=COUNT(*) from Access
select @redundantCount=COUNT(*) --[Number of redundant records, before]
from Access C1
join Access C2 on C1.ID = C2.ID and C1.UserAgent = C2.UserAgent and C1.AuditEnd = C2.AuditBegin
join Audit A1 on A1.ID = C1.AuditBegin
join Audit A2 on A2.ID = C2.AuditBegin
where floor(cast(A1.ChangeDateUTC as real)) = floor(cast(A2.ChangeDateUTC as real))
select @totalCount [Total Number of Records], @redundantCount [Number of Redundant Records], 100.0*@redundantCount/@totalCount [Redundancy Percentage]

begin tran

while 0<(
	select count(*)
	from Access C1
	join Access C2 on C1.ID = C2.ID and C1.UserAgent = C2.UserAgent and C1.AuditEnd = C2.AuditBegin
	join Audit A1 on A1.ID = C1.AuditBegin
	join Audit A2 on A2.ID = C2.AuditBegin
	where floor(cast(A1.ChangeDateUTC as real)) = floor(cast(A2.ChangeDateUTC as real))
)
begin

	declare @id int, @auditBegin int, @auditMiddle int
	declare C cursor for
		select C1.ID, C1.AuditBegin, C1.AuditEnd
		from Access C1
		join Access C2 on C1.ID = C2.ID and C1.UserAgent = C2.UserAgent and C1.AuditEnd = C2.AuditBegin
		join Audit A1 on A1.ID = C1.AuditBegin
		join Audit A2 on A2.ID = C2.AuditBegin
		where floor(cast (A1.ChangeDateUTC as real)) = floor(cast (A2.ChangeDateUTC as real))
	open C
	while 1=1 begin
		fetch next from C into @id , @auditBegin , @auditMiddle
		if @@FETCH_STATUS<>0 break

		delete Access where ID=@id and AuditBegin=@auditBegin
		update Access set AuditBegin=@auditBegin where ID=@id and AuditBegin=@auditMiddle
	end
	close C
	deallocate C

end

select @totalCount=COUNT(*) from Access
select @redundantCount=COUNT(*) --[Number of redundant records, after]
from Access C1
join Access C2 on C1.ID = C2.ID and C1.UserAgent = C2.UserAgent and C1.AuditEnd = C2.AuditBegin
join Audit A1 on A1.ID = C1.AuditBegin
join Audit A2 on A2.ID = C2.AuditBegin
where floor(cast(A1.ChangeDateUTC as real)) = floor(cast(A2.ChangeDateUTC as real))
select @totalCount [Total Number of Records], @redundantCount [Number of Redundant Records], 100.0*@redundantCount/@totalCount [Redundancy Percentage]

--------------------------------------------------
--- Change the following lines to commit changes
rollback 
-- commit
--------------------------------------------------

DBCC DBREINDEX (Access)