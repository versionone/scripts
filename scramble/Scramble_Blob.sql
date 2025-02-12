/*	
*	
 *	It MUST only be run on a COPY of a production database, not on the real one.
 *	When committed, the changes are irreversible.
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1

CREATE TABLE [#Blob](
	[ID] [int] NOT NULL,
	[Hash] [binary](20) NULL,
	[ContentType] [int] NULL
) ON [PRIMARY]

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

insert into #Blob(ID, Hash, ContentType)
select ID, Hash, ContentType
from Blob

ALTER TABLE [dbo].[Attachment] DROP CONSTRAINT [FK_Attachment_Content]
ALTER TABLE [dbo].[Attachment_Now] DROP CONSTRAINT [FK_Attachment_Now_Content]
ALTER TABLE [dbo].[EmbeddedImage] DROP CONSTRAINT [FK_EmbeddedImage_Content]
ALTER TABLE [dbo].[EmbeddedImage_Now] DROP CONSTRAINT [FK_EmbeddedImage_Now_Content]
ALTER TABLE [dbo].[ExpressionImage] DROP CONSTRAINT [FK_ExpressionImage_Content]
ALTER TABLE [dbo].[ExpressionImage_Now] DROP CONSTRAINT [FK_ExpressionImage_Now_Content]
ALTER TABLE [dbo].[ExternalActionInvocation] DROP CONSTRAINT [FK_ExternalActionInvocation_Received]
ALTER TABLE [dbo].[ExternalActionInvocation] DROP CONSTRAINT [FK_ExternalActionInvocation_Sent]
ALTER TABLE [dbo].[ExternalActionInvocation_Now] DROP CONSTRAINT [FK_ExternalActionInvocation_Now_Received]
ALTER TABLE [dbo].[ExternalActionInvocation_Now] DROP CONSTRAINT [FK_ExternalActionInvocation_Now_Sent]
ALTER TABLE [dbo].[Image] DROP CONSTRAINT [FK_Image_Content]
ALTER TABLE [dbo].[Image_Now] DROP CONSTRAINT [FK_Image_Now_Content]
ALTER TABLE [dbo].[WebhookReceipt] DROP CONSTRAINT [FK_WebhookReceipt_HeadersId]
ALTER TABLE [dbo].[WebhookReceipt] DROP CONSTRAINT [FK_WebhookReceipt_ResponseId]

truncate table dbo.Blob
 
SET IDENTITY_INSERT Blob  ON

insert into Blob(ID, Hash, ContentType, Value)
select ID, Hash, ContentType, 0x
from #Blob

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR

SET IDENTITY_INSERT Blob  OFF

ALTER TABLE [dbo].[WebhookReceipt] WITH CHECK ADD CONSTRAINT [FK_WebhookReceipt_ResponseId] FOREIGN KEY([ResponseId]) REFERENCES [dbo].[Blob] ([ID])
ALTER TABLE [dbo].[WebhookReceipt] WITH CHECK ADD CONSTRAINT [FK_WebhookReceipt_HeadersId] FOREIGN KEY([HeadersId]) REFERENCES [dbo].[Blob] ([ID])
ALTER TABLE [dbo].[Image_Now]  WITH NOCHECK ADD  CONSTRAINT [FK_Image_Now_Content] FOREIGN KEY([Content]) REFERENCES [dbo].[Blob] ([ID])
ALTER TABLE [dbo].[Image]  WITH NOCHECK ADD  CONSTRAINT [FK_Image_Content] FOREIGN KEY([Content]) REFERENCES [dbo].[Blob] ([ID])
ALTER TABLE [dbo].[ExternalActionInvocation_Now]  WITH NOCHECK ADD  CONSTRAINT [FK_ExternalActionInvocation_Now_Sent] FOREIGN KEY([Sent]) REFERENCES [dbo].[Blob] ([ID])
ALTER TABLE [dbo].[ExternalActionInvocation_Now]  WITH NOCHECK ADD  CONSTRAINT [FK_ExternalActionInvocation_Now_Received] FOREIGN KEY([Received]) REFERENCES [dbo].[Blob] ([ID])
ALTER TABLE [dbo].[ExternalActionInvocation]  WITH NOCHECK ADD  CONSTRAINT [FK_ExternalActionInvocation_Sent] FOREIGN KEY([Sent]) REFERENCES [dbo].[Blob] ([ID])
ALTER TABLE [dbo].[ExternalActionInvocation]  WITH NOCHECK ADD  CONSTRAINT [FK_ExternalActionInvocation_Received] FOREIGN KEY([Received]) REFERENCES [dbo].[Blob] ([ID])
ALTER TABLE [dbo].[ExpressionImage_Now] WITH CHECK ADD CONSTRAINT [FK_ExpressionImage_Now_Content] FOREIGN KEY([Content]) REFERENCES [dbo].[Blob] ([ID])
ALTER TABLE [dbo].[ExpressionImage] WITH CHECK ADD CONSTRAINT [FK_ExpressionImage_Content] FOREIGN KEY([Content]) REFERENCES [dbo].[Blob] ([ID])
ALTER TABLE [dbo].[EmbeddedImage_Now]  WITH NOCHECK ADD  CONSTRAINT [FK_EmbeddedImage_Now_Content] FOREIGN KEY([Content]) REFERENCES [dbo].[Blob] ([ID])
ALTER TABLE [dbo].[EmbeddedImage]  WITH NOCHECK ADD  CONSTRAINT [FK_EmbeddedImage_Content] FOREIGN KEY([Content]) REFERENCES [dbo].[Blob] ([ID])
ALTER TABLE [dbo].[Attachment_Now]  WITH NOCHECK ADD  CONSTRAINT [FK_Attachment_Now_Content] FOREIGN KEY([Content]) REFERENCES [dbo].[Blob] ([ID])
ALTER TABLE [dbo].[Attachment]  WITH NOCHECK ADD  CONSTRAINT [FK_Attachment_Content] FOREIGN KEY([Content]) REFERENCES [dbo].[Blob] ([ID])

print @rowcount + ' blobs truncated'

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit
DONE:

drop table #Blob
