-- most recent visit per user in a given month
select [Month], ByID, LastAccess=max(ChangeDateUTC) from (
	select ByID, ChangeDateUTC, [Month]=convert(char(7), ChangeDateUTC, 20)
	from Access
	join Audit on Audit.ID=Access.AuditBegin
) X
group by [Month], ByID
having [Month]='2012-08'
