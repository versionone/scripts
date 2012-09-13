-- count of unique users each month
select [Month], UniqueUsers=count(*) from (
	select [Month], ByID from (
		select ByID, [Month]=convert(char(7), ChangeDateUTC, 20)
		from Access
		join Audit on Audit.ID=Access.AuditBegin
	) X
	group by [Month], ByID
) Y
group by [Month]
order by [Month] desc
