set nocount on

declare @totalCount real, @redundantCount real
select @totalCount=COUNT(*) from CustomRelation
select @redundantCount=COUNT(*) --[Number of redundant records, before]
from CustomRelation C1
join CustomRelation C2 on C1.Definition =  C2.Definition and C1.ForeignID = C2.ForeignID and C1.PrimaryID = C2.PrimaryID and C1.AuditEnd = C2.AuditBegin 
select @totalCount [Total Number of Records], @redundantCount [Number of Redundant Records], 100.0*@redundantCount/@totalCount [Redundancy Percentage]



begin tran

while 0<(select count(*)
from CustomRelation C1
join CustomRelation C2 on C1.PrimaryID = C2.PrimaryID and C1.Definition =  C2.Definition and C1.ForeignID = C2.ForeignID and C1.AuditEnd = C2.AuditBegin )
begin

	declare @id int, @definition varchar(100), @value int, @auditBegin int, @auditMiddle int, @auditEnd int
	declare C cursor for
		select C1.PrimaryID, C1.Definition, C1.ForeignID, C1.AuditBegin, C1.AuditEnd, C2.AuditEnd
		from CustomRelation C1
		join CustomRelation C2 on C1.Definition =  C2.Definition and C1.ForeignID = C2.ForeignID and C1.PrimaryID = C2.PrimaryID and C1.AuditEnd = C2.AuditBegin 
	open C
	while 1=1 begin
		fetch next from C into @id , @definition , @value , @auditBegin , @auditMiddle, @auditEnd 
		if @@FETCH_STATUS<>0 break

		delete CustomRelation where PrimaryID=@id and Definition=@definition and AuditBegin=@auditBegin
		update CustomRelation set AuditBegin=@auditBegin where PrimaryID=@id and Definition=@definition and AuditBegin=@auditMiddle
	end
	close C
	deallocate C

end

select @totalCount=COUNT(*) from CustomRelation
select @redundantCount=COUNT(*) --[Number of redundant records, before]
from CustomRelation C1
join CustomRelation C2 on C1.Definition =  C2.Definition and C1.ForeignID = C2.ForeignID and C1.PrimaryID = C2.PrimaryID and C1.AuditEnd = C2.AuditBegin 
select @totalCount [Total Number of Records], @redundantCount [Number of Redundant Records], 100.0*@redundantCount/@totalCount [Redundancy Percentage]



--------------------------------------------------
--- Change the following lines to commit changes
rollback 
--commit
--------------------------------------------------




DBCC DBREINDEX (CustomRelation)
  
