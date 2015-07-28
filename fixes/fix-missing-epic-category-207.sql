/*	
 *	Customer-facing SQL script template
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */

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

-- Begin Body

declare @definition varchar(100), @auditid int
select @definition='List.Order', @auditid = 0

declare @id int, @assettype varchar(100), @name nvarchar(4000), @colorname varchar(100)
select @id=207, @assettype='EpicCategory', @name=N'Initiative',@colorname='seafoam'

declare @namekey int
declare @order int

if not exists (select * from dbo.Rank where Definition=@definition and ID=@id) begin
	select @order=isnull(max([Order])+1, 0) from dbo.Rank where Definition=@definition
	insert dbo.Rank (Definition, ID, [Order]) values (@definition, @id, @order)

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d Rank entries inserted', 0, 1, @rowcount) with nowait
end
else begin
	raiserror('Rank entry already exists', 0, 1) with nowait
end

if not exists (select * from dbo.List_Now where ID=@id) begin
	exec dbo._SaveString @name, @namekey output
	insert dbo.List_Now (ID, AssetType, AuditBegin, Name, ColorName) values (@id, @assettype, @auditid, @namekey, @colorname)

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d List_Now entries inserted', 0, 1, @rowcount) with nowait

	exec dbo._SaveAssetAudit @id, @assettype, @auditid
end
else begin
	raiserror('List_Now entry already exists', 0, 1) with nowait
end

if not exists (select * from dbo.List where ID=@id) begin
	insert dbo.List (ID, AssetType, AuditBegin, Name, AssetState, ColorName)
	select ID, AssetType, AuditBegin, Name, AssetState, ColorName
	from dbo.List_Now where ID=@id

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d List entries inserted', 0, 1, @rowcount) with nowait

	insert dbo.SchemeSelectedValues (SchemeID, ListID, AuditBegin)
	select Scheme.ID, @id, Scheme.AuditBegin from dbo.Scheme_Now Scheme

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
	raiserror('%d SchemeSelectedValues entries inserted', 0, 1, @rowcount) with nowait
end
else begin
	raiserror('List entry already exists', 0, 1) with nowait
end

-- End Body

if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE: