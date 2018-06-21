select AssetType, count(1) asset_count, sum(c) total_changes, max(c) max_change_count, avg(c) avg_change_count
from (
	select AssetType, count(1) c
	from dbo.AssetAudit
	group by AssetType, ID
) _
group by AssetType
order by AssetType
