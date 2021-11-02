/**
* Allstate has decided to capture acceptance dates and names of users who accepted for Stories, Defects and Tests. These
* are normally captured in response to a webhook monitoring Status changes to Story, Defect and Test.
* The webhook processing system has fallen behind so this script will be used to backfill the custom fields used
* to capture this data.
* Story Custom Fields
* - Story.Custom_StoryAcceptedBy (Member.Name of Member who changed Status to Status.Name = 'Accepted')
* - Story.Custom_StoryAcceptedDate (ChangeDate when Status.Name = 'Accepted')
* Defect Custom Fields
* - Defect.Custom_DefectAcceptedBy (Member.Name of Member who changed Status to Status.Name = 'Accepted')
* - Defect.Custom_DefectAcceptedDate (ChangeDate when Status.Name = 'Accepted')
* Test Custom Fields
* - Test.Custom_TestPassedBy (Member.Name of Member who changed Status to Status.Name = 'Passed')
* - Test.Custom_TestPassedDate (ChangeDate when Status.Name = 'Passed')
*/

create proc dbo.__SeedAuditCreate (
    @changereason nvarchar(4000),
	@changecomment nvarchar(4000),
	@changedbyid int,
	@auditid int OUTPUT
) as
begin
	declare @changereasonid int, @changecommentid int
	exec dbo._SaveString @changereason, @changereasonid output
	exec dbo._SaveString @changecomment, @changecommentid output
	insert dbo.Audit(ChangedByID, ChangeDateUTC, ChangeReason, ChangeComment) values(20, GETUTCDATE(), @changereasonid, @changecommentid)
	select @auditid=SCOPE_IDENTITY()
end
go

create proc dbo.__SetCustomText (
	@definition varchar(201),
	@assetid int,
	@auditid int,
	@stringid int
) as
begin
	update dbo.[CustomText] set [AuditEnd]=@auditid
	where ([CustomText].[AuditEnd] is null and [CustomText].[Definition]=@definition and [CustomText].[ID]=@assetid)
	if @stringid is not null begin
		insert dbo.[CustomText]([AuditBegin],[Definition],[ID],[Value])
		values(@auditid,@definition,@assetid,@stringid)
	end
end
go

create proc dbo.__SetCustomDate (
	@definition varchar(201),
	@assetid int,
	@auditid int,
	@datetime datetime
) as
begin
   update dbo.[CustomDate] set [AuditEnd]=@auditid
   where ([CustomDate].[AuditEnd] is null and [CustomDate].[Definition]=@definition and [CustomDate].[ID]=@assetid)
   if @datetime is not null begin
       insert dbo.[CustomDate]([AuditBegin],[Definition],[ID],[Value])
       values(@auditid,@definition,@assetid,@datetime)
   end
end
go

create proc dbo.__BackfillAllStateCustomFields_ForPrimaryWorkitems
	@customDateDefinition varchar(201),
	@customTextDefinition varchar(201),
	@status nvarchar(4000),
	@datefrom datetime,
	@assettype varchar(100),
	@changereason nvarchar(4000) = N'Backfill custom fields',
	@changecomment nvarchar(4000) = N'Backfill custom fields',
	@changedbyid int = 20,
	@savechanges bit = 0
as
begin
	create table #KeySet ([ID] int, [InstigatorStringID] int, [ChangeDateUTC] datetime, [CustomDateID] int, [CustomTextID] int)
	declare @auditid int,@error int, @rowcount varchar(20), @assetcount int, @assetcountprogress int

	;with PrimaryWorkitemsWithStatus as (
		select pwi.ID, pwi.AuditBegin, pwi.AuditEnd, pwi.StatusID, pwi.AssetType, sta.AuditEnd StatusAuditEnd,strings.Value
		from PrimaryWorkitem pwi
		join Status sta on pwi.StatusID = sta.ID
		join List list on sta.ID = list.ID
		join String strings on list.Name = strings.ID
	)

	insert into #KeySet
	select curr.ID, ba.Name, a.ChangeDateUTC, acceptedbydate.ID, acceptedby.ID
	from PrimaryWorkitemsWithStatus curr
	cross apply (
		select top 1 *
		from PrimaryWorkitemsWithStatus prev
		where prev.ID = curr.ID and prev.AuditBegin < curr.AuditBegin and curr.StatusID <> prev.StatusID
		order by prev.AuditBegin desc
	) _
	join dbo.Audit a on a.ID =  _.AuditEnd
	join dbo.BaseAsset_Now ba on a.ChangedByID = ba.ID
	left join dbo.[CustomDate] acceptedbydate on (acceptedbydate.[ID]=curr.[ID] and acceptedbydate.[Definition]=@customDateDefinition and acceptedbydate.[AuditEnd] is null)
	left join dbo.[CustomText] acceptedby on (acceptedby.[ID]=curr.[ID] and acceptedby.[Definition]=@customTextDefinition and acceptedby.[AuditEnd] is null)
	where 
	curr.AuditEnd is null
	and curr.StatusAuditEnd is null
	and (acceptedbydate.ID is null or acceptedby.ID is null)
	and curr.Value = @status
	and a.ChangeDateUTC > @datefrom
	and curr.AssetType = @assettype

	select @assetcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%i %s to backfill.', 1, 1, @assetcount, @assettype)
	set nocount on;
	
	set @assetcountprogress = 0
	begin tran; save tran TX

	declare @ID int, @InstigatorStringID int, @ChangeDateUTC datetime, @CustomDateID int, @CustomTextID int
	declare C cursor local fast_forward for
	select [ID], [InstigatorStringID], [ChangeDateUTC], [CustomDateID], [CustomTextID] 
	from #KeySet
	open C
	while 1=1 begin
		fetch next from C into @ID, @InstigatorStringID, @ChangeDateUTC, @CustomDateID, @CustomTextID
		if @@FETCH_STATUS<>0 break

		set @assetcountprogress = @assetcountprogress + 1

		raiserror('Progress: %i/%i', 1, 1, @assetcountprogress, @assetcount)

		exec __SeedAuditCreate @changereason,@changecomment,@changedbyid,@auditid OUTPUT

		raiserror('Audit created:  @changereason:%s,  @changecomment:%s, @changedbyid:%i, @auditid: %i', 1, 1, @changereason,@changecomment,@changedbyid,@auditid)

		if (@CustomDateID is null)
		begin
			exec dbo.__SetCustomDate @customDateDefinition, @ID, @auditid, @ChangeDateUTC
			if @@ERROR<>0 goto ERR
			raiserror('Custom date filled: @customDateDefinition:%s, @ID:%i, @auditid:%i', 1, 1, @customDateDefinition, @ID, @auditid)
		end
		if (@CustomTextID is null)
		begin
			exec dbo.__SetCustomText @customTextDefinition, @ID, @auditid, @InstigatorStringID
			if @@ERROR<>0 goto ERR
			raiserror('Custom text filled: @customTextDefinition:%s, @ID:%i, @auditid:%i, @InstigatorStringID:%i', 1, 1, @customTextDefinition, @ID, @auditid, @InstigatorStringID)
		end

		exec _SaveAssetAudit @ID, @assettype, @auditid
		if @@ERROR<>0 goto ERR
		raiserror('AssetAudit saved: @ID:%i, @assettype:%s, @auditid:%i', 1, 1, @ID, @assettype, @auditid)
	end
	close C
	deallocate C
	if @saveChanges=1 goto OK
	raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
	ERR: rollback tran TX
	OK: commit
	DONE:
end
go

create proc dbo.__BackfillAllStateCustomFields_ForTests
	@customDateDefinition varchar(201),
	@customTextDefinition varchar(201),
	@status nvarchar(4000),
	@datefrom datetime,
	@assettype varchar(100),
	@changereason nvarchar(4000) = N'Backfill custom fields',
	@changecomment nvarchar(4000) = N'Backfill custom fields',
	@changedbyid int = 20,
	@savechanges bit = 0
as
begin
	create table #KeySet ([ID] int, [InstigatorStringID] int, [ChangeDateUTC] datetime, [CustomDateID] int, [CustomTextID] int)
	declare @auditid int,@error int, @rowcount varchar(20), @assetcount int, @assetcountprogress int

	;with TestsWithStatus as (
		select t.ID, t.AuditBegin, t.AuditEnd, t.StatusID, t.AssetType, list.AuditEnd StatusAuditEnd,strings.Value
		from Test t
		join List list on t.StatusID = list.ID
		join String strings on list.Name = strings.ID
	)

	insert into #KeySet
	select curr.ID, ba.Name, a.ChangeDateUTC, acceptedbydate.ID, acceptedby.ID
	from TestsWithStatus curr
	cross apply (
		select top 1 *
		from TestsWithStatus prev
		where prev.ID = curr.ID and prev.AuditBegin < curr.AuditBegin and curr.StatusID <> prev.StatusID
		order by prev.AuditBegin desc
	) _
	join dbo.Audit a on a.ID =  _.AuditEnd
	join dbo.BaseAsset_Now ba on a.ChangedByID = ba.ID
	left join dbo.[CustomDate] acceptedbydate on (acceptedbydate.[ID]=curr.[ID] and acceptedbydate.[Definition]=@customDateDefinition and acceptedbydate.[AuditEnd] is null)
	left join dbo.[CustomText] acceptedby on (acceptedby.[ID]=curr.[ID] and acceptedby.[Definition]=@customTextDefinition and acceptedby.[AuditEnd] is null)
	where 
	curr.AuditEnd is null
	and curr.StatusAuditEnd is null
	and (acceptedbydate.ID is null or acceptedby.ID is null)
	and curr.Value = @status
	and a.ChangeDateUTC > @datefrom
	and curr.AssetType = @assettype

	select @assetcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%i %s to backfill.', 1, 1, @assetcount, @assettype)
	set nocount on;
	
	set @assetcountprogress = 0
	begin tran; save tran TX

	declare @ID int, @InstigatorStringID int, @ChangeDateUTC datetime, @CustomDateID int, @CustomTextID int
	declare C cursor local fast_forward for
	select [ID], [InstigatorStringID], [ChangeDateUTC], [CustomDateID], [CustomTextID] 
	from #KeySet
	open C
	while 1=1 begin
		fetch next from C into @ID, @InstigatorStringID, @ChangeDateUTC, @CustomDateID, @CustomTextID
		if @@FETCH_STATUS<>0 break

		set @assetcountprogress = @assetcountprogress + 1

		raiserror('Progress: %i/%i', 1, 1, @assetcountprogress, @assetcount)

		exec __SeedAuditCreate @changereason,@changecomment,@changedbyid,@auditid OUTPUT

		raiserror('Audit created:  @changereason:%s,  @changecomment:%s, @changedbyid:%i, @auditid: %i', 1, 1, @changereason,@changecomment,@changedbyid,@auditid)

		if (@CustomDateID is null)
		begin
			exec dbo.__SetCustomDate @customDateDefinition, @ID, @auditid, @ChangeDateUTC
			if @@ERROR<>0 goto ERR
			raiserror('Custom date filled: @customDateDefinition:%s, @ID:%i, @auditid:%i', 1, 1, @customDateDefinition, @ID, @auditid)
		end
		if (@CustomTextID is null)
		begin
			exec dbo.__SetCustomText @customTextDefinition, @ID, @auditid, @InstigatorStringID
			if @@ERROR<>0 goto ERR
			raiserror('Custom text filled: @customTextDefinition:%s, @ID:%i, @auditid:%i, @InstigatorStringID:%i', 1, 1, @customTextDefinition, @ID, @auditid, @InstigatorStringID)
		end

		exec _SaveAssetAudit @ID, @assettype, @auditid
		if @@ERROR<>0 goto ERR
		raiserror('AssetAudit saved: @ID:%i, @assettype:%s, @auditid:%i', 1, 1, @ID, @assettype, @auditid)
	end
	close C
	deallocate C
	if @saveChanges=1 goto OK
	raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
	ERR: rollback tran TX
	OK: commit
	DONE:
end
go