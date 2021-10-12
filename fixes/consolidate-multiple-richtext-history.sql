/*
 *	Consolidate field history records, on configurable time threshold (@timeThreshold) in minutes.
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = '1'.
 */

@saveChanges nvarchar(100) = '0',
declare @table sysname = 'Test',
@tableName varchar(100) = 'Test',
@timeThreshold nvarchar(10) = '5',
@field varchar(max) = 'ExpectedResults'

declare @colsAB varchar(max)
select @colsAB=(
	select REPLACE(' and (A.{col}=B.{col} or (A.{col} is null and B.{col} is null))', '{col}', quotename(COLUMN_NAME))
	from INFORMATION_SCHEMA.COLUMNS C
	where C.TABLE_NAME=@table and COLUMN_NAME not in ('ID','AssetType','AuditBegin', @field, 'AuditEnd')
	for xml path('')
)

declare @template2 varchar(max) = '
	create table #assets(ID int not null, CurrentAuditID int not null, NextAuditID int not null)
	create table #suspect(ID int not null, CurrentAuditID int not null, NextAuditID int not null)
	create table #bad(ID int not null, CurrentAuditID int not null, NextAuditID int not null)

	set nocount on; begin tran; save tran TX
	-- Asset Rows
	;with H as (
		select AA.ID, AA.AssetType, AuditID, R=ROW_NUMBER() OVER(partition by AA.ID, AA.AssetType order by AuditID)
		from dbo.AssetAudit AA
	)
	insert #assets(ID, CurrentAuditID, NextAuditID)
	select aH.ID, aH.AuditID, bH.AuditID
	from H as aH
	join dbo.[@table] aAsset on aAsset.ID=aH.ID and aAsset.AssetType=aH.AssetType and aH.AuditID = aAsset.AuditBegin
	join H as bH on bH.ID=aH.ID and aH.AssetType=bH.AssetType and bH.R=aH.R+1
	join dbo.[@table] bAsset on bAsset.ID=bH.ID and bAsset.AssetType=bH.AssetType and bH.AuditID = bAsset.AuditBegin
	if (@saveChanges != ''1'') select NULL as ''#assets'', * from #assets

	-- Consecutive Asset changes
	insert #suspect(ID, CurrentAuditID, NextAuditID)
	select Assets.ID, Assets.CurrentAuditID, Assets.NextAuditID
	from #assets as Assets
	join dbo.[@table] currentAsset on currentAsset.ID=Assets.ID and currentAsset.AuditBegin=Assets.CurrentAuditID
	join dbo.[@table] nextAsset on nextAsset.ID=Assets.ID and nextAsset.AuditBegin=Assets.NextAuditID
	join dbo.Audit currentA on currentA.ID = Assets.CurrentAuditID
	join dbo.Audit nextA on nextA.ID = Assets.NextAuditID
	WHERE
	ISNULL(currentA.ChangedByID,-1) = ISNULL(nextA.ChangedByID,-1)  -- Consecutive changes from the same user
	AND DATEDIFF(mi,currentA.ChangeDateUTC,nextA.ChangeDateUTC) <= @timeThreshold --Time threshold / period / lapse.
	AND	ISNULL(currentAsset.[@field],-1) != ISNULL(nextAsset.[@field],-1) --@FieldName has changed
	if (@saveChanges != ''1'') select NULL as ''#suspect'', * from #suspect

	-- consecutive redundant entries
	insert #bad(ID, CurrentAuditID, NextAuditID)
	select _.ID, CurrentAuditID, NextAuditID
	from #suspect _
	join dbo.[@table] A on A.ID=_.ID and A.AuditBegin=_.CurrentAuditID
	join dbo.[@table] B on B.ID=_.ID and B.AuditEnd=_.CurrentAuditID AND ISNULL(B.[@field],-1) != ISNULL(A.[@field],-1) {@colsAB}
	if (@saveChanges != ''1'') select NULL as ''#bad'', * from #bad

	-- Rows to purge
	select NULL as ''will purge'', cAsset.ID, cAsset.AssetType, cAsset.AuditBegin, a.ChangedByID, a.ChangeDateUTC
	from #bad b
	join dbo.[@table] cAsset ON cAsset.ID=b.ID and cAsset.AuditBegin=b.CurrentAuditID
	join dbo.Audit a on a.ID = b.CurrentAuditID

	-- Purge
	delete dbo.[@table]
	from #bad
	where [@table].ID=#bad.ID and [@table].AuditBegin=#bad.CurrentAuditID

	-- Check for errors
	declare @error int, @rowcount int
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror(''%d %s.%s historical records purged'', 0, 1, @rowcount, @tableName, @fldName)
	if @rowcount=0 goto FINISHED

	--re-stitch Asset history
	;with H as (
		select ID, AuditBegin, AuditEnd, R=ROW_NUMBER() over(partition by ID order by AuditBegin)
		from dbo.[@table]
	)
	update dbo.[@table] set AuditEnd=B.AuditBegin
	from H A
	left join H B on A.ID=B.ID and A.R+1=B.R
	where [@table].ID=A.ID and [@table].AuditBegin=A.AuditBegin
	and isnull(A.AuditEnd,-1)<>isnull(B.AuditBegin,-1)

	-- sync up Table_Now with history tips from Table
	alter table dbo.@tblNow disable trigger all
	update dbo.@tblNow set AuditBegin=[@table].AuditBegin
	from dbo.[@table]
	where [@table].ID=@tblNow.ID and [@table].AuditEnd is null and [@table].AuditBegin<>@tblNow.AuditBegin
	alter table dbo.@tblNow enable trigger all

	-- Log number of _Now records synced
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror(''%d records syncd'', 0, 1, @rowcount) with nowait

	if @saveChanges = ''1'' begin
		DBCC DBREINDEX([@table])
		exec dbo.AssetAudit_Rebuild
		DBCC DBREINDEX(AssetAudit)
	end

	FINISHED:
	if (@saveChanges = ''1'') goto OK
	raiserror(''Rolling back changes.  To commit changes, set saveChanges="1"'',16,1)
	ERR: rollback tran TX
	OK: commit

	drop table #bad
	drop table #suspect
	drop table #assets
'
declare @sql varchar(max) = @template2
select @sql = replace(@sql, token, value) from (values
	('[@table]', quotename(@table)),
	('@tableName', quotename(@tableName, '''')),
	('@tblNow', quotename(@tableName + '_Now')),
	('@saveChanges', quotename(@saveChanges, '''')),
	('@timeThreshold', @timeThreshold),
	('[@field]', quotename(@field)),
	('@fldName', quotename(@field, '''')),
	('{colsAB}', @colsAB)
) _(token, value)

--print @sql
exec(@sql)
