/*
Change the content in the blob table
*/
declare @attachmentAssetName int
exec dbo._SaveString 'Name of my Attachment Asset', @attachmentAssetName out

UPDATE Blob
SET Blob.Value = 0x454582696865678469684545
WHERE ID IN (
    SELECT Attachment.Content
    FROM Attachment, String
    WHERE Attachment.Name = String.ID
    AND String.ID in (@attachmentAssetName)
)

/*
Change the Content-Type of the updated records to text/plain
*/

declare @textplain int
exec dbo._SaveString 'text/plain', @textplain out
--select * from String where ID=@textplain

disable trigger all on dbo.Attachment_Now

update dbo.Attachment
set ContentType=@textplain
where Attachment.Name in (
    select ID from dbo.String
    where String.ID in (@attachmentAssetName)
)

update dbo.Attachment_Now
set ContentType=@textplain
where Attachment.Name in (
    select ID from dbo.String
    where String.ID in (@attachmentAssetName)
)

enable trigger all on dbo.Attachment_Now