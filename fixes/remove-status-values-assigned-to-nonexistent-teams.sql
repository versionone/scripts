/*	
 *	Remove StoryStatus values assigned to a Team that does not exist
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1

set nocount on; begin tran;
save tran TX

delete from List_Now 
where AssetType='StoryStatus' 
and (TeamID is not null and TeamID not in (select distinct ID from Team_Now))

delete from List 
where AssetType='StoryStatus' 
and (TeamID is not null and TeamID not in (select distinct ID from Team))

delete from Status_Now 
where AssetType='StoryStatus' 
and ID not in (select ID from List_Now where AssetType='StoryStatus')

delete from Status 
where AssetType='StoryStatus' 
and ID not in (select ID from List where AssetType='StoryStatus')

if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE:
