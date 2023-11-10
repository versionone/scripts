create procedure dbo.NukeWorkitemEmbeddedImages
    @number varchar(20)
as
begin
    declare @number_number int = substring(@number, patindex('%[0-9]%', @number), len(@number))
    declare @assetid int

    select @assetid = ID 
    from Workitem_Now
    where Number = @number_number
    and AssetType = (
        select Name
        from AssetType_Now
        where NumberPattern like left(@number, patindex('%-%', @number)) + '%'
    )

    if (@@rowcount <> 1)
    begin
        raiserror('Invalid Workitem number', 0, 1)
        return
    end

    declare @blankimage varbinary(max) = 0x89504e470d0a1a0a0000000d4948445200000001000000010100000000376ef9240000001049444154789c626001000000ffff03000006000557bfabd40000000049454e44ae426082

    update Blob 
    set Value = @blankimage
    where ID in (
        select Content
        from dbo.EmbeddedImage
        where AssetID = @assetid
    )
    and cast(Value as varbinary(max)) <> @blankimage

    raiserror('%d Embedded Images nuked', 0, 1, @@rowcount) with nowait
end
