create or alter function [dbo].[OidSplit] (
    @oid varchar(200)
)
returns table
as
return
(
    select 
        substring(@oid, 1, charindex(':', @oid) - 1) COLLATE Latin1_General_BIN as AssetType,
        cast(substring(@oid, charindex(':', @oid) + 1, len(@oid)) as int) as ID
)
GO

create or alter function [dbo].[ExtractHashesFromUrls]
(
    @richtextcol nvarchar(max)
)
returns table
as
return
(
    with recursivecte as (
        select
            charindex('downloadblob.img/', @richtextcol) + len('downloadblob.img/') as startpos,
            charindex('"', @richtextcol, charindex('downloadblob.img/', @richtextcol)) as endpos
        where charindex('downloadblob.img/', @richtextcol) > 0

        union all

        select
            charindex('downloadblob.img/', @richtextcol, endpos) + len('downloadblob.img/') as startpos,
            charindex('"', @richtextcol, charindex('downloadblob.img/', @richtextcol, endpos)) as endpos
        from
            recursivecte
        where
            charindex('downloadblob.img/', @richtextcol, endpos) > 0
    )
	select distinct substring(
            @richtextcol,
            startpos,
            endpos - startpos
        ) as Hash
	from
        recursivecte
    where
        charindex('downloadblob.img/', @richtextcol, startpos) > 0
)
GO

create or alter function dbo.ReplaceBetween(@rickText varchar(max), @startMarker varchar(200), @endMarker varchar(200), @replacement varchar(max))
returns varchar(max)
as
begin
    declare @StartIndex int = charindex(@startMarker, @rickText);

    while @StartIndex > 0
    begin
        set @rickText = stuff(
            @rickText,
            @StartIndex,
            charindex(@endMarker, substring(@rickText, @StartIndex, len(@rickText)))+LEN(@endMarker)-1,
            @replacement
        );
        set @StartIndex = charindex(@startMarker, @rickText, @StartIndex + len(@replacement));
    end;

    return @rickText;
end;
GO

create or alter procedure dbo.NukeWorkitemEmbeddedImages
    @oid varchar(20),
	@saveChanges bit
as
begin
    declare @Id int, @assetType varchar(100)

	declare @error int, @rowcount int

    select @Id = ba.ID, @assetType = ba.AssetType
    from BaseAsset_Now ba
	join dbo.OidSplit(@oid) oid on ba.ID = oid.ID and ba.AssetType = oid.AssetType

    if (@@rowcount <> 1)
    begin
        raiserror('Invalid asset oid', 0, 1)
        return
    end

    declare @blankimage varbinary(max) = 0x89504e470d0a1a0a0000000d4948445200000001000000010100000000376ef9240000001049444154789c626001000000ffff03000006000557bfabd40000000049454e44ae426082
    declare @blankimageHash binary(20) = CONVERT([binary](20),hashbytes('SHA1',CONVERT(varbinary(max),@blankimage)))
	declare @blankImageBase64 varchar(max) = CAST(N'' AS XML).value('xs:base64Binary(xs:hexBinary(sql:variable("@blankimage")))', 'VARCHAR(MAX)')
    declare @imgpng int
    
    begin tran; save tran TX

    exec dbo._SaveString N'img/png', @imgpng output

    if not exists(select * from Blob where Hash = @blankimageHash)
        insert into dbo.Blob(Hash, ContentType, Value)
        values (@blankimageHash, @imgpng, @blankimage)

    update Blob 
    set Value = @blankimage, ContentType=@imgpng
    where ID in (
        select Content
        from dbo.EmbeddedImage
        where AssetID = @Id
    )
    and cast(Value as varbinary(max)) <> @blankimage

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR
    raiserror('%d Embedded Images nuked', 0, 1, @rowcount) with nowait


	DECLARE cRichTextFields CURSOR FORWARD_ONLY FOR
	select ls.ID, cast (ls.Value as nvarchar(max))
	from BaseAsset bs
	left join CustomLongText clt on bs.ID = clt.ID
	left join LongString ls on ls.ID in (bs.Description, clt.Value)
	where bs.ID = @Id and ls.ID is not null

	OPEN cRichTextFields;

	DECLARE @LongStringID int, @Value nvarchar(max)

	FETCH NEXT FROM cRichTextFields INTO @LongStringID, @Value

	WHILE @@FETCH_STATUS = 0
	BEGIN
		delete
        from Blob 
		where Hash in (
            select Hash
            from dbo.ExtractHashesFromUrls(@Value)
            where Hash <> @blankimageHash
		)

		select @rowcount=@@ROWCOUNT, @error=@@ERROR
		if @error<>0 goto ERR
		raiserror('%d hash referenced images removed from Blob table %d', 0, 1, @rowcount, @LongStringID) with nowait

        update LongString
	    set LongString.Value = dbo.ReplaceBetween (LongString.Value, 'downloadblob.img/', '"', 'downloadblob.img/' + CONVERT(NVARCHAR(MAX), @blankimageHash, 2))
        where ID = @LongStringID

		select @rowcount=@@ROWCOUNT, @error=@@ERROR
		if @error<>0 goto ERR
		raiserror('%d hash referenced images nuked for long string %d', 0, 1, @rowcount, @LongStringID) with nowait

		FETCH NEXT FROM cRichTextFields INTO @LongStringID, @Value
	END

	CLOSE cRichTextFields;
	DEALLOCATE cRichTextFields

	update LongString
	set LongString.Value = dbo.ReplaceBetween (LongString.Value, 'data:image', '"','data:image/png;base64,' + @blankImageBase64)
	from BaseAsset bs
	left join CustomLongText clt on bs.ID = clt.ID
	where bs.ID = @Id and bs.ID is not null
	and LongString.ID in (bs.Description, clt.Value)
	and charindex(cast(LongString.Value as varchar(max)),'data:image') > 0 

	select @rowcount=@@ROWCOUNT, @error=@@ERROR
	if @error<>0 goto ERR

	raiserror('%d base64 images replaced', 0, 1, @rowcount) with nowait

	if @saveChanges=1 goto OK
	raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
	ERR: rollback tran TX
	OK: commit
end