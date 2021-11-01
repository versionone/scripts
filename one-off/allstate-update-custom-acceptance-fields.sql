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

create proc dbo.__BackfillAllStateCustomFields
	@customDateDefinition varchar(201),
	@customTextDefinition varchar(201),
	@datefrom datetime,
	@assettype varchar(100),
	@dryrun bit
as
begin
	create table #KeySet ([ID] int, [InstigatorStringID] int, [ChangeDateUTC] datetime, [CustomDateID] int, [CustomTextID] int)

	;with PrimaryWorkitemsWithStatus as (
		select pwi2.*, strings2.Value
		from PrimaryWorkitem pwi2
		join Status sta2 on pwi2.StatusID = sta2.ID
		join List list2 on sta2.ID = list2.ID
		join String strings2 on list2.Name = strings2.ID
	)

	insert into #KeySet
	select curr.ID, inst.ID, a.ChangeDateUTC, acceptedbydate.ID, acceptedby.ID
	from PrimaryWorkitemsWithStatus curr
	cross apply (
		select top 1 *
		from PrimaryWorkitemsWithStatus prev
		where prev.ID = curr.ID and prev.AuditBegin < curr.AuditBegin and curr.StatusID <> prev.StatusID
		order by prev.AuditBegin desc
	) _
	join dbo.Audit a on a.ID =  _.AuditEnd
	join dbo.BaseAsset_Now ba on a.ChangedByID = ba.ID
	join dbo.String inst on ba.Name = inst.ID
	left join dbo.[CustomDate] acceptedbydate on (acceptedbydate.[ID]=curr.[ID] and acceptedbydate.[Definition]=@customDateDefinition and acceptedbydate.[AuditEnd] is null)
	left join dbo.[CustomText] acceptedby on (acceptedby.[ID]=curr.[ID] and acceptedby.[Definition]=@customTextDefinition and acceptedby.[AuditEnd] is null)
	where curr.AuditEnd is null
	and (acceptedbydate.ID is null or acceptedby.ID is null)
	and curr.Value = 'Accepted'
	and a.ChangeDateUTC > @datefrom
	and curr.AssetType = @assettype

	declare @changereason nvarchar(4000) = N'Backfill custom fields',
	@changecomment nvarchar(4000) = N'Backfill custom fields',
	@changedbyid int = 20,
	@auditid int

	declare @ID int, @InstigatorStringID int, @ChangeDateUTC datetime, @CustomDateID int, @CustomTextID int
	declare C cursor local fast_forward for
	select ID from dbo.AssetType_Now
	open C
	while 1=1 begin
		fetch next from C into @ID, @InstigatorStringID, @ChangeDateUTC, @CustomDateID, @CustomTextID
		if @@FETCH_STATUS<>0 break

		exec __SeedAuditCreate @changereason,@changecomment,@changedbyid,@auditid OUTPUT

		if (@CustomDateID is null)
			exec dbo.__SetCustomDate @customDateDefinition, @ID, @auditid, @ChangeDateUTC
		if (@CustomTextID is null)
			exec dbo.__SetCustomText @customTextDefinition, @ID, @auditid, @InstigatorStringID

		exec _SaveAssetAudit @ID, @assettype, @auditid
	end
	close C
	deallocate C

end
go