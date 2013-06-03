/*	
 *	Convert custom fields from Stories to Epics.
 *	
 *	Before running this script, create and publish a new custom field
 *	on the Epic type to hold the converted values.
 *	
 *	Set @storyField to the name of the old Story custom field.
 *	Set @epicField to the name of the new Epic custom field.
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @storyField varchar(100); --set @storyField='Custom_SFDCAccountID'
declare @epicField varchar(100); --set @epicField='Custom_aText'
declare @saveChanges bit; --set @saveChanges = 1
declare @supportedVersions varchar(1000); select @supportedVersions='12.*, 13.*'

-- Ensure the correct database version
BEGIN
	declare @sep char(2); select @sep=', '
	if not exists(select *
		from dbo.SystemConfig
		join (
		select SUBSTRING(@supportedVersions, C.Value+1, CHARINDEX(@sep, @supportedVersions+@sep, C.Value+1)-C.Value-1) as Value
		from dbo.Counter C
		where C.Value < DataLength(@supportedVersions) and SUBSTRING(@sep+@supportedVersions, C.Value+1, DataLength(@sep)) = @sep
		) Version on SystemConfig.Value like REPLACE(Version.Value, '*', '%') and SystemConfig.Name = 'Version'
	) begin
			raiserror('Only supported on version(s) %s',16,1, @supportedVersions)
			goto DONE
	end
END

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

declare @storyDefinition varchar(201), @storyAttributeType varchar(100), @storyRelatedTo varchar(100)
declare @epicDefinition varchar(201), @epicAttributeType varchar(100), @epicRelatedTo varchar(100)

select @storyDefinition=AT.Name+'.'+Def.Name, @storyAttributeType=AttributeType, @storyRelatedTo=RAT.Name
from dbo.AttributeDefinition_Now Def 
join dbo.AssetType_Now AT on AT.ID=Def.AssetID
join dbo.AssetTypeBaseHierarchy H on H.AncestorID=AT.ID and AuditEnd is null
join dbo.AssetType_Now StoryAT on StoryAT.ID=H.DescendantID
left join dbo.RelationDefinition_Now Rel on Rel.ID=Def.ID
left join dbo.AssetType_Now RAT on RAT.ID=RelatedAssetTypeID
where StoryAT.Name='Story' and Def.IsCustom=1 and Def.Name=@storyField

select @epicDefinition=AT.Name+'.'+Def.Name, @epicAttributeType=AttributeType, @epicRelatedTo=RAT.Name
from dbo.AttributeDefinition_Now Def 
join dbo.AssetType_Now AT on AT.ID=Def.AssetID
join dbo.AssetTypeBaseHierarchy H on H.AncestorID=AT.ID and AuditEnd is null
join dbo.AssetType_Now StoryAT on StoryAT.ID=H.DescendantID
left join dbo.RelationDefinition_Now Rel on Rel.ID=Def.ID
left join dbo.AssetType_Now RAT on RAT.ID=RelatedAssetTypeID
where StoryAT.Name='Epic' and Def.IsCustom=1 and Def.Name=@epicField

if (@storyDefinition is null) begin
	raiserror('%s is not a custom field on Story',16,2, @storyField)
	goto ERR
end

if (@epicDefinition is null) begin
	raiserror('%s is not a custom field on Epic',16,3, @epicField)
	goto ERR
end

if (@storyAttributeType <> @epicAttributeType) begin
	raiserror('Cannot convert %s (%s) to %s (%s)',16,4, @storyDefinition, @storyAttributeType, @epicDefinition, @epicAttributeType)
	goto ERR
end

declare @map table(StoryID int not null, EpicID int not null, primary key (StoryID), unique (EpicID))

insert @map
select distinct MorphedFromID StoryID, ID EpicID
from dbo.Epic
where MorphedFromID is not null

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR

if (@storyAttributeType='Boolean' and @epicAttributeType='Boolean') begin
	insert dbo.CustomBoolean(Definition, ID, AuditBegin, AuditEnd, Value)
	select @epicDefinition, EpicID, AuditBegin, AuditEnd, Value
	from @map Map
	join dbo.CustomBoolean on Definition=@storyDefinition and ID=StoryID
	
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	print @rowcount + ' records converted from ' + @storyDefinition + ' to ' + @epicDefinition

	;with A as (
		select Definition, ID, AuditBegin, AuditEnd, Value, R=row_number() over(partition by Definition, ID order by AuditBegin)
		from dbo.CustomBoolean
	)
	update A
	set AuditEnd=B.AuditBegin
	from A B
	where A.Definition=@epicDefinition and B.Definition=@epicDefinition and A.ID=B.ID and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	if @rowcount<>0 print @rowcount + ' conflicting records restitched'
end

else if (@storyAttributeType='Date' and @epicAttributeType='Date') begin
	insert dbo.CustomDate(Definition, ID, AuditBegin, AuditEnd, Value)
	select @epicDefinition, EpicID, AuditBegin, AuditEnd, Value
	from @map Map
	join dbo.CustomDate on Definition=@storyDefinition and ID=StoryID
	
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	print @rowcount + ' records converted from ' + @storyDefinition + ' to ' + @epicDefinition

	;with A as (
		select Definition, ID, AuditBegin, AuditEnd, Value, R=row_number() over(partition by Definition, ID order by AuditBegin)
		from dbo.CustomDate
	)
	update A
	set AuditEnd=B.AuditBegin
	from A B
	where A.Definition=@epicDefinition and B.Definition=@epicDefinition and A.ID=B.ID and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	if @rowcount<>0 print @rowcount + ' conflicting records restitched'
end

else if (@storyAttributeType='LongText' and @epicAttributeType='LongText') begin
	insert dbo.CustomLongText(Definition, ID, AuditBegin, AuditEnd, Value)
	select @epicDefinition, EpicID, AuditBegin, AuditEnd, Value
	from @map Map
	join dbo.CustomLongText on Definition=@storyDefinition and ID=StoryID
	
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	print @rowcount + ' records converted from ' + @storyDefinition + ' to ' + @epicDefinition

	;with A as (
		select Definition, ID, AuditBegin, AuditEnd, Value, R=row_number() over(partition by Definition, ID order by AuditBegin)
		from dbo.CustomLongText
	)
	update A
	set AuditEnd=B.AuditBegin
	from A B
	where A.Definition=@epicDefinition and B.Definition=@epicDefinition and A.ID=B.ID and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	if @rowcount<>0 print @rowcount + ' conflicting records restitched'
end

else if (@storyAttributeType='Numeric' and @epicAttributeType='Numeric') begin
	insert dbo.CustomNumeric(Definition, ID, AuditBegin, AuditEnd, Value)
	select @epicDefinition, EpicID, AuditBegin, AuditEnd, Value
	from @map Map
	join dbo.CustomNumeric on Definition=@storyDefinition and ID=StoryID
	
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	print @rowcount + ' records converted from ' + @storyDefinition + ' to ' + @epicDefinition

	;with A as (
		select Definition, ID, AuditBegin, AuditEnd, Value, R=row_number() over(partition by Definition, ID order by AuditBegin)
		from dbo.CustomNumeric
	)
	update A
	set AuditEnd=B.AuditBegin
	from A B
	where A.Definition=@epicDefinition and B.Definition=@epicDefinition and A.ID=B.ID and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	if @rowcount<>0 print @rowcount + ' conflicting records restitched'
end

else if (@storyAttributeType='Text' and @epicAttributeType='Text') begin
	insert dbo.CustomText(Definition, ID, AuditBegin, AuditEnd, Value)
	select @epicDefinition, EpicID, AuditBegin, AuditEnd, Value
	from @map Map
	join dbo.CustomText on Definition=@storyDefinition and ID=StoryID
	
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	print @rowcount + ' records converted from ' + @storyDefinition + ' to ' + @epicDefinition

	;with A as (
		select Definition, ID, AuditBegin, AuditEnd, Value, R=row_number() over(partition by Definition, ID order by AuditBegin)
		from dbo.CustomText
	)
	update A
	set AuditEnd=B.AuditBegin
	from A B
	where A.Definition=@epicDefinition and B.Definition=@epicDefinition and A.ID=B.ID and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	if @rowcount<>0 print @rowcount + ' conflicting records restitched'
end

else if (@storyAttributeType='Relation' and @epicAttributeType='Relation') begin
	if (@storyRelatedTo <> @epicRelatedTo) begin
		raiserror('Cannot convert %s (%s) to %s (%s)',16,4, @storyDefinition, @storyRelatedTo, @epicDefinition, @epicRelatedTo)
		goto ERR
	end
	
	insert dbo.CustomRelation(Definition, PrimaryID, ForeignID, AuditBegin, AuditEnd)
	select @epicDefinition, EpicID, ForeignID, AuditBegin, AuditEnd
	from @map Map
	join dbo.CustomRelation on Definition=@storyDefinition and PrimaryID=StoryID
	
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	print @rowcount + ' records converted from ' + @storyDefinition + ' to ' + @epicDefinition

	;with A as (
		select Definition, PrimaryID, ForeignID, AuditBegin, AuditEnd, R=row_number() over(partition by Definition, PrimaryID, ForeignID order by AuditBegin)
		from dbo.CustomRelation
	)
	update A
	set AuditEnd=B.AuditBegin
	from A B
	where A.Definition=@epicDefinition and B.Definition=@epicDefinition and A.PrimaryID=B.PrimaryID and A.ForeignID=B.ForeignID and A.R+1=B.R and (A.AuditEnd is null or A.AuditEnd>B.AuditBegin)

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	if @rowcount<>0 print @rowcount + ' conflicting records restitched'
end

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE: