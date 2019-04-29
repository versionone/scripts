select ID, AssetType, Cnt from
(
	select *, ROW_NUMBER() over(partition by AssetType order by Cnt desc) r
	from (select count(1) Cnt, ID, AssetType from dbo.AssetAudit group by ID, AssetType having count(1) > 50) _
) __
where r <= 100
