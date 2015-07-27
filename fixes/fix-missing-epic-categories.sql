/*	
 *	Customer-facing SQL script template
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */

GO

create proc dbo.__List (
	@id int,
	@assettype varchar(100),
	@name nvarchar(4000),
	@colorname varchar(100)
) as

declare @definition varchar(100), @auditid int
select @definition='List.Order', @auditid = 0

declare @namekey int
declare @order int

if not exists (select * from dbo.Rank where Definition=@definition and ID=@id) begin
	select @order=isnull(max([Order])+1, 0) from dbo.Rank where Definition=@definition
	insert dbo.Rank (Definition, ID, [Order]) values (@definition, @id, @order)
end

if not exists (select * from dbo.List_Now where ID=@id) begin
	exec dbo._SaveString @name, @namekey output
	insert dbo.List_Now (ID, AssetType, AuditBegin, Name, ColorName) values (@id, @assettype, @auditid, @namekey, @colorname)
	exec dbo._SaveAssetAudit @id, @assettype, @auditid
end

if not exists (select * from dbo.List where ID=@id) begin
	insert dbo.List (ID, AssetType, AuditBegin, Name, AssetState, ColorName)
	select ID, AssetType, AuditBegin, Name, AssetState, ColorName
	from dbo.List_Now where ID=@id

	insert dbo.SchemeSelectedValues (SchemeID, ListID, AuditBegin)
	select Scheme.ID, @id, Scheme.AuditBegin from dbo.Scheme_Now Scheme
end
GO

create proc dbo.__Status (
	@id int,
	@assettype varchar(100),
	@name nvarchar(4000),
	@colorname varchar(100),
	@rollupstate tinyint
) as

declare @auditid int
select @auditid = 0

if not exists (select * from dbo.Status_Now where ID=@id) and not exists (select * from dbo.List_Now where ID=@id) begin
	insert dbo.Status_Now (ID, AssetType, AuditBegin, RollupState) values (@id, @assettype, @auditid, @rollupstate)
end

if not exists (select * from dbo.Status where ID=@id) and not exists (select * from dbo.List where ID=@id) begin
	insert dbo.Status (ID, AssetType, AuditBegin, RollupState)
	select ID, AssetType, AuditBegin, RollupState
	from dbo.Status_Now where ID=@id
end

exec dbo.__List @id, @assettype, @name, @colorname
GO

declare @saveChanges bit; --set @saveChanges = 1
declare @supportedVersions varchar(1000); select @supportedVersions='15.*'


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

declare @error int, @rowcount int
set nocount on; begin tran; save tran TX

exec dbo.__Status 199, 'EpicStatus', N'Define', 'wisteria', 0
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d EpicStatus entries inserted', 0, 1, @rowcount) with nowait

exec dbo.__Status 200, 'EpicStatus', N'Breakdown', 'denim', 0
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d EpicStatus entries inserted', 0, 1, @rowcount) with nowait

exec dbo.__Status 201, 'EpicStatus', N'Build', 'cerulean', 64
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d EpicStatus entries inserted', 0, 1, @rowcount) with nowait

exec dbo.__Status 202, 'EpicStatus', N'Test', 'jungle', 64
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d EpicStatus entries inserted', 0, 1, @rowcount) with nowait

exec dbo.__Status 206, 'EpicStatus', N'Deploy', 'shamrock', 128
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d EpicStatus entries inserted', 0, 1, @rowcount) with nowait
	

exec dbo.__List 203, 'EpicPriority', N'Low', 'seafoam'
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d EpicPriority entries inserted', 0, 1, @rowcount) with nowait

exec dbo.__List 204, 'EpicPriority', N'Medium', 'dandelion'
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d EpicPriority entries inserted', 0, 1, @rowcount) with nowait

exec dbo.__List 205, 'EpicPriority', N'High', 'watermelon'
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d EpicPriority entries inserted', 0, 1, @rowcount) with nowait


exec dbo.__List 207, 'EpicCategory', N'Initiative', 'seafoam'
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d EpicCategory entries inserted', 0, 1, @rowcount) with nowait

exec dbo.__List 208, 'EpicCategory', N'Feature', 'sunglow'
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d EpicCategory entries inserted', 0, 1, @rowcount) with nowait

exec dbo.__List 209, 'EpicCategory', N'Sub-Feature', 'fuschia'
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d EpicCategory entries inserted', 0, 1, @rowcount) with nowait

exec dbo.__List 210, 'EpicCategory', N'Non-Functional', 'shadow'
	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d EpicCategory entries inserted', 0, 1, @rowcount) with nowait


if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE: