/*
 *	Convert a custom field of a specified list type to another custom field.
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @originalListTypeName varchar(100)
declare @newListTypeName varchar(100)
declare @originalCustomFieldName varchar(201)
declare @newCustomFieldName varchar(201)

declare @error int, @rowcount int
set nocount on; begin tran; save tran TX

declare @map table (
	drID int,
	rcID int
);
insert @map select dr.ID, rc.ID from
	(select List_Now.ID, Value name from List_Now join String on String.ID = Name where AssetType = @originalListTypeName and AssetState < 128) dr join
	(select  List_Now.ID, Value name from List_Now join String on String.ID = Name where AssetType = @newListTypeName and AssetState < 128) rc
	on dr.name = rc.name;

insert CustomRelation (Definition, PrimaryID, ForeignID, AuditBegin, AuditEnd)
	select Definition=@newCustomFieldName, PrimaryID, ForeignID = rcID, AuditBegin, AuditEnd
		 from CustomRelation cr join @map map on map.drID = ForeignID
		 where Definition = @originalCustomFieldName
		 and not exists (select * from CustomRelation where Definition = @newCustomFieldName and PrimaryID = cr.PrimaryID);
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d %s records migrated to %s', 0, 1, @rowcount, @originalCustomFieldName, @newCustomFieldName) with nowait


if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE:
