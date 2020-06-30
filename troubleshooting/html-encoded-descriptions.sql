/* Query to determine how many incorrectly HTML encoded descriptions due to D-16993 */
select ba.ID, strs.Value, ls.Value from dbo.LongString ls
inner join dbo.BaseAsset_Now ba on ba.Description = ls.ID
inner join dbo.String strs on ba.Name = strs.ID
where ls.Value like '%&lt;img class="asset-icon" src="/VersionOne.Web/IconProxy.mvc/Resolve?assetType=Member%';