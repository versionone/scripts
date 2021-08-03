/*
 *	Purges all vestiges of a project.
 *
 *	Set @scopeToPurge to the ID of the project to purge.
 *	Set @allowRecursion=1 to purge child projects recursively.
 *	Set @saveMembers=1 to keep Member data
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @commitChanges = 1.
 *		To make changes WITHOUT A TRANSACTION, no possibility of rollback, and possible data corruption, set @commitChanges = 2
 */

declare @commitChanges tinyint; --set @commitChanges = 1; --set @commitChanges = 2
declare @scopeToPurge int; --set @scopeToPurge = 54198
declare @allowRecursion bit; --set @allowRecursion = 1
declare @saveMembers bit; -- set @saveMembers = 1

-- Ensure the correct database version
declare @supportedVersion varchar(10); set @supportedVersion = '21.2'
if (@supportedVersion is not null) begin
	if not exists (select * from SystemConfig where Name='Version' and Value like @supportedVersion + '.%') begin
		raiserror('This script can only run on a %s VersionOne database',16,1, @supportedVersion)
		goto DONE
	end
end

declare @is_auto_update_stats_async_on bit, @user_access_desc nvarchar(60)
select
	@is_auto_update_stats_async_on = is_auto_update_stats_async_on,
	@user_access_desc=user_access_desc
from sys.databases where database_id=DB_ID()

if (@user_access_desc <> 'SINGLE_USER') begin
	if (@is_auto_update_stats_async_on = 1) begin
		raiserror('Disabling async auto-update states', 0, 1) with nowait
		alter database current set AUTO_UPDATE_STATISTICS_ASYNC OFF
	end
	raiserror('Putting database into SINGLE_USER mode', 0, 1) with nowait
	alter database current set SINGLE_USER with rollback immediate
end

exec sp_MSforeachtable @command1='disable trigger all on ?'

declare @error int, @rowcount varchar(20)
set nocount on;

if (@commitChanges = 2) begin raiserror('Making changes with no transaction!', 0, 1) with nowait; goto TX_STARTED end
begin tran; save tran TX
TX_STARTED:

-- Ensure the Scope exists
if not exists (select * from Scope_Now where ID=@scopeToPurge) begin
	raiserror('Scope:%i does not exist',16,2, @scopeToPurge)
	goto ERR
end

-- Disallow cascading to children scopes
if isnull(@allowRecursion,0)<>1  begin
	if (select COUNT(*) from Scope_Now where ParentID=@scopeToPurge) > 0 begin
		select AssetType, ID, ParentID from Scope_Now where ParentID=@scopeToPurge
		select @rowcount=@@ROWCOUNT
		raiserror('Scope:%i has %s children, so it cannot be purged.  To allow recursion, pass @allowRecursion=1',16,3, @scopeToPurge, @rowcount)
		goto ERR
	end
end

---
--- Rack 'em
---

declare @doomed table(doomed int not null primary key)
declare @safeScopes table(safeScope int not null primary key)
declare @safeMembers table(safeMember int not null primary key)
declare @safeTeams table(safeTeam int not null primary key)

-- NEVER purge Member:20 !
insert @safeMembers values(20)

-- save all non-deleted Members, if requested
insert @safeMembers
select ID from BaseAsset_Now where @saveMembers=1 and AssetType='Member' and AssetState<255
except
select safeMember from @safeMembers

-- doom the seed Scope
insert @doomed values(@scopeToPurge)

-- doom the current children of doomed Scopes, recursively
while 1=1 begin
	insert @doomed select ID from Scope_Now join @doomed on doomed=ParentID
	except select doomed from @doomed
	if @@ROWCOUNT=0 break
end

-- NEVER purge Scope:0 !
delete @doomed where doomed = 0

-- all other Scopes are safe
insert @safeScopes
select ID from Scope_Now
except
select doomed from @doomed

-- current/past owners of safe Scopes are safe
insert @safeMembers
select distinct OwnerID from Scope join @safeScopes on safeScope=ID where OwnerID is not null
except select safeMember from @safeMembers

-- doom TestSuites of doomed Scopes, except those ever used by safe Scopes
insert @doomed
select distinct TestSuiteID from Scope join @doomed on doomed=ID where TestSuiteID is not null
except
select distinct TestSuiteID from Scope join @safeScopes on safeScope=ID where TestSuiteID is not null

-- doom TestRuns belonging to doomed TestSuites
insert @doomed
select distinct ID from TestRun_Now join @doomed on doomed=TestSuiteID

-- doom all Schedules of doomed Scopes, except those ever used by safe Scopes
insert @doomed
select distinct ScheduleID from Scope join @doomed on doomed=ID where ScheduleID is not null
except
select distinct ScheduleID from Scope join @safeScopes on safeScope=ID where ScheduleID is not null

-- doom Timeboxes currently belonging to doomed  Schedules
insert @doomed
select ID from Timebox_Now join @doomed on doomed=ScheduleID

-- current owners of safe Timeboxes are safe
insert @safeMembers
select distinct OwnerID from Timebox_Now where ID not in (select doomed from @doomed) and OwnerID is not null
except select safeMember from @safeMembers

-- doom all Schemes of doomed Scopes, except those ever used by safe Scopes
insert @doomed
select distinct SchemeID from Scope join @doomed on doomed=ID
except
select distinct SchemeID from Scope join @safeScopes on safeScope=ID

-- doom Goals that live in doomed Scopes
insert @doomed
select ID from Goal_Now join @doomed on doomed=ScopeID

-- doom Roadmaps that live in doomed Scopes
insert @doomed
select ID from Roadmap_Now join @doomed on doomed=ScopeID

-- doom Issues that live in doomed Scopes
insert @doomed
select ID from Issue_Now join @doomed on doomed=ScopeID

-- current owners of safe Issues are safe
insert @safeMembers
select distinct OwnerID from Issue_Now where ID not in (select doomed from @doomed) and OwnerID is not null
except select safeMember from @safeMembers

-- current teams of safe Issues are safe
insert @safeTeams
select distinct TeamID from Issue_Now where ID not in (select doomed from @doomed) and TeamID is not null
except select safeTeam from @safeTeams

-- doom Requests that live in doomed Scopes
insert @doomed
select ID from Request_Now join @doomed on doomed=ScopeID

-- current owners of safe Requests are safe
insert @safeMembers
select distinct OwnerID from Request_Now where ID not in (select doomed from @doomed) and OwnerID is not null
except select safeMember from @safeMembers

-- doom Retrospectives that live in doomed Scopes
insert @doomed
select ID from Retrospective_Now join @doomed on doomed=ScopeID

-- current facilitators of safe Retrospectives are safe
insert @safeMembers
select distinct FacilitatedByID from Retrospective_Now where ID not in (select doomed from @doomed) and FacilitatedByID is not null
except select safeMember from @safeMembers

-- current teams of safe Retrospectives are safe
insert @safeTeams
select distinct TeamID from Retrospective_Now where ID not in (select doomed from @doomed) and TeamID is not null
except select safeTeam from @safeTeams

-- doom RegressionTests belonging to doomed Scopes
insert @doomed
select ID from RegressionTest_Now join @doomed on doomed=ScopeID

-- current Teams of safe RegressionTests are safe
insert @safeTeams
select distinct TeamID from RegressionTest_Now where ID not in (select doomed from @doomed) and TeamID is not null
except select safeTeam from @safeTeams

-- current owners of safe RegressionTests are safe
insert @safeMembers
select distinct MemberID from RegressionTestOwners where AuditEnd is null and RegressionTestID not in (select doomed from @doomed)
except select safeMember from @safeMembers

-- doom RegressionPlans belonging to doomed Scopes
insert @doomed
select ID from RegressionPlan_Now join @doomed on doomed=ScopeID

-- current Owners of safe RegressionPlans are safe
insert @safeMembers
select distinct OwnerID from RegressionPlan_Now where ID not in (select doomed from @doomed) and OwnerID is not null
except select safeMember from @safeMembers

-- doom RegressionSuites belonging to doomed RegressionPlans
insert @doomed
select ID from RegressionSuite_Now join @doomed on doomed=RegressionPlanID

-- current Owners of safe RegressionSuites are safe
insert @safeMembers
select distinct OwnerID from RegressionSuite_Now where ID not in (select doomed from @doomed) and OwnerID is not null
except select safeMember from @safeMembers

-- doom Environments belonging to doomed Scopes
insert @doomed
select ID from Environment_Now join @doomed on doomed=ScopeID

-- doom Workitems that live in doomed Scopes
insert @doomed
select ID from Workitem_Now join @doomed on doomed=ScopeID

-- current teams of safe Workitems are safe
insert @safeTeams
select distinct TeamID from Workitem_Now where ID not in (select doomed from @doomed) and TeamID is not null
except select safeTeam from @safeTeams

-- current owners of safe Workitems are safe
insert @safeMembers
select distinct MemberID from WorkitemOwners where AuditEnd is null and WorkitemID not in (select doomed from @doomed)
except select safeMember from @safeMembers

-- current Customers of safe Themes are safe
insert @safeMembers
select distinct CustomerID from Theme_Now where ID not in (select doomed from @doomed) and CustomerID is not null
except select safeMember from @safeMembers

-- current Customers of safe Stories are safe
insert @safeMembers
select distinct CustomerID from Story_Now where ID not in (select doomed from @doomed) and CustomerID is not null
except select safeMember from @safeMembers

-- current Verifiers of safe Defects are safe
insert @safeMembers
select distinct VerifiedByID from Defect_Now where ID not in (select doomed from @doomed) and VerifiedByID is not null
except select safeMember from @safeMembers

-- doom TestSets belonging to doomed RegressionSuites
insert @doomed
select ID from TestSet_Now join @doomed on doomed=RegressionSuiteID
except select doomed from @doomed

-- current Customers of safe Tasks are safe
insert @safeMembers
select distinct CustomerID from Task_Now where ID not in (select doomed from @doomed) and CustomerID is not null
except select safeMember from @safeMembers

-- doom BuildProjects ever associated with doomed Scopes, except those ever associated with safe Scopes
insert @doomed
select distinct BuildProjectID from BuildProjectScopes join @doomed on doomed=ScopeID
except
select distinct BuildProjectID from BuildProjectScopes join @safeScopes on safeScope=ScopeID

-- doom BuildRuns belonging to doomed BuildProjects
insert @doomed
select ID from BuildRun_Now join @doomed on doomed=BuildProjectID

-- doom ChangeSets ever associated with doomed BuildRuns, except those ever associated with safe BuildRuns
insert @doomed
select distinct ChangeSetID from BuildRunChangeSets join @doomed on doomed=BuildRunID
except
select distinct ChangeSetID from BuildRunChangeSets join @safeScopes on safeScope=BuildRunID

-- doom Capacities of doomed Scopes or Timeboxes
insert @doomed
select ID from Capacity_Now join @doomed on doomed=ScopeID
union
select ID from Capacity_Now join @doomed on doomed=TimeboxID

-- Members with safe Capacity are safe
insert @safeMembers
select distinct MemberID from Capacity_Now where ID not in (select doomed from @doomed) and MemberID is not null
except select safeMember from @safeMembers

-- Teams with safe Capacity are safe
insert @safeTeams
select distinct TeamID from Capacity_Now where ID not in (select doomed from @doomed) and TeamID is not null
except select safeTeam from @safeTeams

-- doom Actuals of doomed Scopes or Timeboxes or Workitems
insert @doomed
select ID from Actual_Now join @doomed on doomed=ScopeID
union
select ID from Actual_Now join @doomed on doomed=TimeboxID
union
select ID from Actual_Now join @doomed on doomed=WorkitemID

-- Members with safe Actuals are safe
insert @safeMembers
select distinct MemberID from Actual_Now where ID not in (select doomed from @doomed) and MemberID is not null
except select safeMember from @safeMembers

-- Teams with safe Actuals are safe
insert @safeTeams
select distinct TeamID from Actual_Now where ID not in (select doomed from @doomed) and TeamID is not null
except select safeTeam from @safeTeams

-- doom Teams that are not safe
insert @doomed
select ID from Team_Now
except select safeTeam from @safeTeams

-- doom List values of doomed Teams
insert @doomed
select ID from List_Now join @doomed on doomed=TeamID

-- Members assigned to safe Scopes are safe
insert @safeMembers
select distinct MemberID from ScopeMemberACL join @safeScopes on safeScope=ScopeID where RoleID<>0 or Owner<>0
except select safeMember from @safeMembers

-- doom Members assigned to doomed Scopes, except safe Members
insert @doomed
select distinct MemberID from ScopeMemberACL join @doomed on doomed=ScopeID where RoleID<>0 or Owner<>0
except select safeMember from @safeMembers

-- doom Budgets attached to doomed Projects
insert @doomed
select ID from Budget_Now join @doomed on doomed=ScopeID
except select doomed from @doomed

-- doom Allocations for doomed Budgets and doomed Assets
insert @doomed
select DISTINCT ID from Allocation_Now join @doomed on doomed=BudgetID or doomed=AssetID

-- doom child Allocations of doomed Allocations
while 1=1 begin
	insert @doomed
	select ID from Allocation_Now join @doomed on doomed=ParentID
	except select doomed from @doomed
	if @@ROWCOUNT=0 break
end

-- doom Budgets that have only doomed Allocations
insert @doomed
select distinct BudgetID from Allocation_Now join @doomed on doomed=ID
except
select distinct BudgetID from Allocation_Now where ID not in (select doomed from @doomed)
except select doomed from @doomed

-- doom MessageReceipts that are for doomed Recipients
insert @doomed
select ID from MessageReceipt_Now join @doomed on doomed=RecipientID

-- doom Messages that have no un-doomed MessageReceipts
insert @doomed
select distinct MessageID from MessageReceipt_Now join @doomed on doomed=ID
except
select distinct MessageID from MessageReceipt_Now where ID not in (select doomed from @doomed)

-- doom Messages that are about doomed assets (recursively)
while 1=1 begin
	insert @doomed select ID from Message_Now join @doomed on doomed=AssetID
	except select doomed from @doomed
	if @@ROWCOUNT=0 break
end

-- doom MessageReceipts that are for doomed Messages
insert @doomed
select ID from MessageReceipt_Now join @doomed on doomed=MessageID
except select doomed from @doomed

--doom StrategicThemes in doomed Scopes
insert @doomed
select ID from StrategicTheme_Now join @doomed on doomed=ScopeID

-- doom Milestones that live in doomed Scopes
insert @doomed
select ID from Milestone_Now join @doomed on doomed=ScopeID

-- doom BaseAssets that are secured by doomed Scopes
-- NOTE: This should always be done after all other BaseAsset types, in case other secured items are added by more specific inserts
-- BUT before any non-BaseAsset that is doomed by a relation to BaseAsset
insert @doomed
select ID from BaseAsset_Now join @doomed on doomed=SecurityScopeID
except select doomed from @doomed

-- doom Attachments on doomed assets
insert @doomed
select ID from Attachment_Now join @doomed on doomed=AssetID

-- doom Links on doomed assets
insert @doomed
select ID from Link_Now join @doomed on doomed=AssetID

-- doom ExternalActions that have a doomed TriggerType
insert @doomed
select ID from ExternalAction_Now join @doomed on doomed=TriggerTypeID

-- doom ExternalActionInvocations invoked on doomed assets or caused by doomed ExternalActions
insert @doomed
select ID from ExternalActionInvocation_Now join @doomed on doomed=InvokedOnID or doomed=CausedByID

-- doom Notes about doomed assets or personal to doomed Members
insert @doomed
select ID from Note_Now join @doomed on doomed=AssetID
union
select ID from Note_Now join @doomed on doomed=PersonalToID

-- doom Notes in response to doomed Notes
while 1=1 begin
	insert @doomed
	select ID from Note_Now join @doomed on doomed=InResponseToID
	except select doomed from @doomed
	if @@ROWCOUNT=0 break
end

-- doom EmbeddedImages on doomed assets
insert @doomed
select ID from EmbeddedImage_Now join @doomed on doomed=AssetID

-- doom Expressions in doomed Conversations
insert @doomed
select distinct ID from Expression_Now join @doomed on doomed=BelongsToID

-- doom ScopeLabels ever used by doomed Scopes, except those ever used by safe Scopes
insert @doomed
select distinct ScopeLabelID from ScopeScopeLabels join @doomed on doomed=ScopeID
except
select distinct ScopeLabelID from ScopeScopeLabels where ScopeID not in (select doomed from @doomed)

-- doom MemberLabels ever used by doomed Members, except those ever used by safe Members
insert @doomed
select distinct MemberLabelID from MemberMemberLabels join @doomed on doomed=MemberID
except
select distinct MemberLabelID from MemberMemberLabels where MemberID not in (select doomed from @doomed)

-- doom Subscriptions of doomed Members
insert @doomed select ID from Subscription_Now join @doomed on doomed=SubscriberID
-- doom SubscriptionTerms belonging to doomed Subscriptions
insert @doomed select ID from SubscriptionTerm_Now join @doomed on doomed=SubscriptionID

-- doom Accesses by doomed Members
insert @doomed select ID from Access_Now join @doomed on doomed=ByID

-- doom IdeasUserCaches of doomed Members
insert @doomed select ID from IdeasUserCache_Now join @doomed on doomed=MemberID

-- Snapshots?
insert @doomed select ID from Snapshot_Now join @doomed on doomed=AssetID

-- doom Rooms tied to doomed Scopes or doomed Schedules
insert @doomed
select ID from Room_Now join @doomed on doomed=ScopeID
union
select ID from Room_Now join @doomed on doomed=ScheduleID

-- doom avatar Images of doomed Members and mascot Images of doomed Rooms
insert @doomed
select AvatarID from Member join @doomed on doomed=ID where AvatarID is not null
union
select MascotID from Room join @doomed on doomed=ID where MascotID is not null

-- doom Publications of doomed Members
insert @doomed
select ID from Publication_Now join @doomed on doomed=AuthorID

-- doom Grants belonging to doomed Members
insert @doomed
select ID from Grant_Now join @doomed on doomed=OwnerID

-- doom Timesheets of doomed Members
insert @doomed
select ID from Timesheet_Now join @doomed on doomed=MemberID

-- doom SavedViews owned by doomed Members or pegged to doomed Scopes
insert @doomed
select ID from SavedView_Now join @doomed on doomed=OwnerID or doomed=ScopeID

------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------

---
--- Whack 'em
---
raiserror('EpicDependencies', 0, 1) with nowait
delete EpicDependencies from @doomed where doomed=EpicID1 or doomed=EpicID2
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s EpicDependencies purged', 0, 1, @rowcount) with nowait

raiserror('BaseAssetTaggedWith', 0, 1) with nowait
delete BaseAssetTaggedWith from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s BaseAssetTaggedWithAll purged', 0, 1, @rowcount) with nowait

raiserror('SchemeImportantFields', 0, 1) with nowait
delete SchemeImportantFields from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s SchemeImportantFields purged', 0, 1, @rowcount) with nowait

raiserror('IDSource', 0, 1) with nowait
delete IDSource from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s IDs purged', 0, 1, @rowcount) with nowait

raiserror('AssetAuditChangedByLast', 0, 1) with nowait
delete AssetAuditChangedByLast from @doomed where doomed=ID or doomed=ChangedByID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s AssetAuditChangedByLasts purged', 0, 1, @rowcount) with nowait

raiserror('Audits', 0, 1) with nowait
update Audit set ChangedByID=null from @doomed where doomed=ChangedByID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Audits updated', 0, 1, @rowcount) with nowait

raiserror('Custom Attributes', 0, 1) with nowait
delete CustomBoolean from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Custom booleans purged', 0, 1, @rowcount) with nowait
delete CustomDate from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Custom dates purged', 0, 1, @rowcount) with nowait
delete CustomLongText from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Custom longtexts purged', 0, 1, @rowcount) with nowait
delete CustomNumeric from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Custom numerics purged', 0, 1, @rowcount) with nowait
delete CustomRelation from @doomed where doomed=PrimaryID or doomed=ForeignID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Custom relations purged', 0, 1, @rowcount) with nowait
delete CustomText from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Custom texts purged', 0, 1, @rowcount) with nowait

raiserror('Ranks', 0, 1) with nowait
delete Rank from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Ranks purged', 0, 1, @rowcount) with nowait

delete dbo.EffectiveACL
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR

raiserror('Snapshots', 0, 1) with nowait
delete Snapshot_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Snapshot from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Snapshots purged', 0, 1, @rowcount) with nowait

raiserror('IdeasUserCache', 0, 1) with nowait
delete IdeasUserCache_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete IdeasUserCache from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s IdeasUserCaches purged', 0, 1, @rowcount) with nowait

raiserror('Accesses', 0, 1) with nowait
delete Access_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Access from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Accesses purged', 0, 1, @rowcount) with nowait

raiserror('Subscriptions', 0, 1) with nowait
delete SubscriptionTerm_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete SubscriptionTerm from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s SubscriptionTerms purged', 0, 1, @rowcount) with nowait
delete Subscription_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Subscription from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Subscriptions purged', 0, 1, @rowcount) with nowait

raiserror('Labels', 0, 1) with nowait
delete DefectVersions from @doomed where doomed=VersionLabelID
select @error=@@ERROR; if @error<>0 goto ERR
delete MemberMemberLabels from @doomed where doomed=MemberLabelID
select @error=@@ERROR; if @error<>0 goto ERR
delete ScopeScopeLabels from @doomed where doomed=ScopeLabelID
select @error=@@ERROR; if @error<>0 goto ERR
delete ExpressionSpaceFollowers from @doomed where doomed=ExpressionSpaceID
select @error=@@ERROR; if @error<>0 goto ERR
delete Label_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Label from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Labels purged', 0, 1, @rowcount) with nowait

raiserror('SavedViews', 0, 1) with nowait
delete SavedView_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete SavedView from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s SavedViews purged', 0, 1, @rowcount) with nowait

raiserror('Expressions', 0, 1) with nowait
delete ExpressionMentions from @doomed where doomed=ExpressionID
select @error=@@ERROR; if @error<>0 goto ERR
delete Expression_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Expression_Now set InReplyToID=null from @doomed where doomed=InReplyToID
select @error=@@ERROR; if @error<>0 goto ERR
update Expression_Now set AuthorID=null from @doomed where doomed=AuthorID
select @error=@@ERROR; if @error<>0 goto ERR
delete Expression from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Expression set InReplyToID=null from @doomed where doomed=InReplyToID
select @error=@@ERROR; if @error<>0 goto ERR
update Expression set AuthorID=null from @doomed where doomed=AuthorID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Expressions purged', 0, 1, @rowcount) with nowait

raiserror('Conversations', 0, 1) with nowait
delete ConversationParticipants from @doomed where doomed=ConversationID
select @error=@@ERROR; if @error<>0 goto ERR
delete Conversation_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Conversation_Now set RoomID=null from @doomed where doomed=RoomID
select @error=@@ERROR; if @error<>0 goto ERR
update Conversation_Now set ExpressionSpaceID=null from @doomed where doomed=ExpressionSpaceID
select @error=@@ERROR; if @error<>0 goto ERR
delete Conversation from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Conversation set RoomID=null from @doomed where doomed=RoomID
select @error=@@ERROR; if @error<>0 goto ERR
update Conversation set ExpressionSpaceID=null from @doomed where doomed=ExpressionSpaceID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Conversations purged', 0, 1, @rowcount) with nowait

raiserror('EmbeddedImages', 0, 1) with nowait
delete EmbeddedImage_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete EmbeddedImage from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s EmbeddedImages purged', 0, 1, @rowcount) with nowait

raiserror('Notes', 0, 1) with nowait
delete NoteInResponseToHierarchy from @doomed where doomed=AncestorID or doomed=DescendantID
select @error=@@ERROR; if @error<>0 goto ERR
delete Note_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Note_Now set InResponseToID=null from @doomed where doomed=InResponseToID
select @error=@@ERROR; if @error<>0 goto ERR
update Note_Now set PersonalToID=null from @doomed where doomed=PersonalToID
select @error=@@ERROR; if @error<>0 goto ERR
delete Note from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Note set InResponseToID=null from @doomed where doomed=InResponseToID
select @error=@@ERROR; if @error<>0 goto ERR
update Note set PersonalToID=null from @doomed where doomed=PersonalToID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Notes purged', 0, 1, @rowcount) with nowait

raiserror('ExternalActionInvocations', 0, 1) with nowait
delete ExternalActionInvocation_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete ExternalActionInvocation from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s ExternalActionInvocations purged', 0, 1, @rowcount) with nowait

raiserror('ExternalActions', 0, 1) with nowait
delete ExternalAction_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update ExternalAction_Now set TriggerTypeID=null from @doomed where doomed=TriggerTypeID
select @error=@@ERROR; if @error<>0 goto ERR
delete ExternalAction from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update ExternalAction set TriggerTypeID=null from @doomed where doomed=TriggerTypeID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s ExternalActions purged', 0, 1, @rowcount) with nowait

raiserror('Links', 0, 1) with nowait
delete Link_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Link from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Links purged', 0, 1, @rowcount) with nowait

raiserror('Attachments', 0, 1) with nowait
delete Attachment_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Attachment_Now set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
delete Attachment from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Attachment set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Attachments purged', 0, 1, @rowcount) with nowait

raiserror('MessageReceipts', 0, 1) with nowait
delete MessageReceipt_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete MessageReceipt from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s MessageReceipts purged', 0, 1, @rowcount) with nowait

raiserror('Messages', 0, 1) with nowait
delete MessageRecipients from @doomed where doomed=MessageID
select @error=@@ERROR; if @error<>0 goto ERR
delete Message_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Message_Now set AssetID=null from @doomed where doomed=AssetID
select @error=@@ERROR; if @error<>0 goto ERR
delete Message from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Message set AssetID=null from @doomed where doomed=AssetID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Messages purged', 0, 1, @rowcount) with nowait

raiserror('Actuals', 0, 1) with nowait
delete Actual_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Actual_Now set TimeboxID=null from @doomed where doomed=TimeboxID
select @error=@@ERROR; if @error<>0 goto ERR
update Actual_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
delete Actual from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Actual set TimeboxID=null from @doomed where doomed=TimeboxID
select @error=@@ERROR; if @error<>0 goto ERR
update Actual set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Actuals purged', 0, 1, @rowcount) with nowait

raiserror('BuildRuns', 0, 1) with nowait
delete BuildRunChangeSets from @doomed where doomed=BuildRunID
select @error=@@ERROR; if @error<>0 goto ERR
delete BuildRunCompletesPrimaryWorkitems from @doomed where doomed=BuildRunID
select @error=@@ERROR; if @error<>0 goto ERR
delete BuildRunFoundDefects from @doomed where doomed=BuildRunID
select @error=@@ERROR; if @error<>0 goto ERR
delete BuildRun_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update BuildRun_Now set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update BuildRun_Now set SourceID=null from @doomed where doomed=SourceID
select @error=@@ERROR; if @error<>0 goto ERR
delete BuildRun from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update BuildRun set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update BuildRun set SourceID=null from @doomed where doomed=SourceID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s BuildRuns purged', 0, 1, @rowcount) with nowait

raiserror('BuildProjects', 0, 1) with nowait
delete BuildProjectScopes from @doomed where doomed=BuildProjectID
select @error=@@ERROR; if @error<>0 goto ERR
delete BuildProject_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete BuildProject from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s BuildProjects purged', 0, 1, @rowcount) with nowait

raiserror('Bundles', 0, 1) with nowait
delete BundleChangeSets from @doomed where doomed=BundleID
select @error=@@ERROR; if @error<>0 goto ERR
delete Bundle_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Bundle_Now set PhaseID=null from @doomed where doomed=PhaseID
select @error=@@ERROR; if @error<>0 goto ERR
delete Bundle from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Bundle set PhaseID=null from @doomed where doomed=PhaseID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Bundles purged', 0, 1, @rowcount) with nowait

raiserror('ChangeSets', 0, 1) with nowait
delete BundleChangeSets from @doomed where doomed=ChangeSetID
select @error=@@ERROR; if @error<>0 goto ERR
delete BuildRunChangeSets from @doomed where doomed=ChangeSetID
select @error=@@ERROR; if @error<>0 goto ERR
delete ChangeSetPrimaryWorkitems from @doomed where doomed=ChangeSetID
select @error=@@ERROR; if @error<>0 goto ERR
delete ChangeSet_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete ChangeSet from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s ChangeSets purged', 0, 1, @rowcount) with nowait

raiserror('Capacities', 0, 1) with nowait
delete TeamCapacityExcludedMembers from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
delete Capacity_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Capacity_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update Capacity_Now set MemberID=null from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete Capacity from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Capacity set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update Capacity set MemberID=null from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Capacities purged', 0, 1, @rowcount) with nowait

raiserror('TestRuns', 0, 1) with nowait
delete TestRun_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete TestRun from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s TestRuns purged', 0, 1, @rowcount) with nowait

raiserror('TestSuite', 0, 1) with nowait
delete TestSuite_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete TestSuite from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s TestSuites purged', 0, 1, @rowcount) with nowait

raiserror('RegressionSuite', 0, 1) with nowait
delete RegressionSuiteRegressionTests from @doomed where doomed=RegressionSuiteID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionSuite_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update RegressionSuite_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionSuite from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionSuite set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s RegressionSuites purged', 0, 1, @rowcount) with nowait

raiserror('RegressionTests', 0, 1) with nowait
delete RegressionSuiteRegressionTests from @doomed where doomed=RegressionTestID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionTestOwners from @doomed where doomed=RegressionTestID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionTest_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest_Now set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest_Now set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest_Now set GeneratedFromID=null from @doomed where doomed=GeneratedFromID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionTest from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest set GeneratedFromID=null from @doomed where doomed=GeneratedFromID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s RegressionTests purged', 0, 1, @rowcount) with nowait

raiserror('RegressionPlans', 0, 1) with nowait
delete RegressionPlan_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update RegressionPlan_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionPlan from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionPlan set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s RegressionPlans purged', 0, 1, @rowcount) with nowait

raiserror('Goals', 0, 1) with nowait
delete GoalTargetedBy from @doomed where doomed=GoalID
select @error=@@ERROR; if @error<>0 goto ERR
delete WorkitemGoals from @doomed where doomed=GoalID
select @error=@@ERROR; if @error<>0 goto ERR
delete Goal_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Goal from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Goal_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update Goal_Now set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update Goal_Now set PriorityID=null from @doomed where doomed=PriorityID
select @error=@@ERROR; if @error<>0 goto ERR
update Goal set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update Goal set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update Goal set PriorityID=null from @doomed where doomed=PriorityID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Goals purged', 0, 1, @rowcount) with nowait

raiserror('Retrospectives', 0, 1) with nowait
delete RetrospectiveIssues from @doomed where doomed=RetrospectiveID
select @error=@@ERROR; if @error<>0 goto ERR
delete Retrospective_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Retrospective_Now set FacilitatedByID=null from @doomed where doomed=FacilitatedByID
select @error=@@ERROR; if @error<>0 goto ERR
update Retrospective_Now set TimeboxID=null from @doomed where doomed=TimeboxID
select @error=@@ERROR; if @error<>0 goto ERR
update Retrospective_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
delete Retrospective from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Retrospective set FacilitatedByID=null from @doomed where doomed=FacilitatedByID
select @error=@@ERROR; if @error<>0 goto ERR
update Retrospective set TimeboxID=null from @doomed where doomed=TimeboxID
select @error=@@ERROR; if @error<>0 goto ERR
update Retrospective set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Retrospectives purged', 0, 1, @rowcount) with nowait

raiserror('Requests', 0, 1) with nowait
delete RequestIssues from @doomed where doomed=RequestID
select @error=@@ERROR; if @error<>0 goto ERR
delete RequestPrimaryWorkitems from @doomed where doomed=RequestID
select @error=@@ERROR; if @error<>0 goto ERR
delete RequestEpics from @doomed where doomed=RequestID
select @error=@@ERROR; if @error<>0 goto ERR
delete Request_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Request_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
update Request_Now set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update Request_Now set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update Request_Now set PriorityID=null from @doomed where doomed=PriorityID
select @error=@@ERROR; if @error<>0 goto ERR
update Request_Now set ResolutionReasonID=null from @doomed where doomed=ResolutionReasonID
select @error=@@ERROR; if @error<>0 goto ERR
delete Request from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Request set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
update Request set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update Request set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update Request set PriorityID=null from @doomed where doomed=PriorityID
select @error=@@ERROR; if @error<>0 goto ERR
update Request set ResolutionReasonID=null from @doomed where doomed=ResolutionReasonID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Requests purged', 0, 1, @rowcount) with nowait

raiserror('Issues', 0, 1) with nowait
delete IssueBlockedPrimaryWorkitems from @doomed where doomed=IssueID
select @error=@@ERROR; if @error<>0 goto ERR
delete IssuePrimaryWorkitems from @doomed where doomed=IssueID
select @error=@@ERROR; if @error<>0 goto ERR
delete IssueEpics from @doomed where doomed=IssueID
select @error=@@ERROR; if @error<>0 goto ERR
delete IssueBlockedEpics from @doomed where doomed=IssueID
select @error=@@ERROR; if @error<>0 goto ERR
delete RequestIssues from @doomed where doomed=IssueID
select @error=@@ERROR; if @error<>0 goto ERR
delete RetrospectiveIssues from @doomed where doomed=IssueID
select @error=@@ERROR; if @error<>0 goto ERR
delete Issue_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Issue_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue_Now set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue_Now set PriorityID=null from @doomed where doomed=PriorityID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue_Now set ResolutionReasonID=null from @doomed where doomed=ResolutionReasonID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
delete Issue from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue set PriorityID=null from @doomed where doomed=PriorityID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue set ResolutionReasonID=null from @doomed where doomed=ResolutionReasonID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Issues purged', 0, 1, @rowcount) with nowait

raiserror('Tasks', 0, 1) with nowait
delete Task_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Task_Now set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
update Task_Now set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update Task_Now set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
delete Task from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Task set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
update Task set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update Task set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Tasks purged', 0, 1, @rowcount) with nowait

raiserror('Tests', 0, 1) with nowait
delete Test_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Test_Now set GeneratedFromID=null from @doomed where doomed=GeneratedFromID
select @error=@@ERROR; if @error<>0 goto ERR
update Test_Now set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update Test_Now set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
delete Test from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Test set GeneratedFromID=null from @doomed where doomed=GeneratedFromID
select @error=@@ERROR; if @error<>0 goto ERR
update Test set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update Test set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Tests purged', 0, 1, @rowcount) with nowait

raiserror('TestSets', 0, 1) with nowait
delete TestSet_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update TestSet_Now set EnvironmentID=null from @doomed where doomed=EnvironmentID
select @error=@@ERROR; if @error<>0 goto ERR
delete TestSet from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update TestSet set EnvironmentID=null from @doomed where doomed=EnvironmentID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s TestSets purged', 0, 1, @rowcount) with nowait

raiserror('Environments', 0, 1) with nowait
delete Environment_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Environment from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Environments purged', 0, 1, @rowcount) with nowait

raiserror('Defects', 0, 1) with nowait
delete BuildRunFoundDefects from @doomed where doomed=DefectID
select @error=@@ERROR; if @error<>0 goto ERR
delete DefectAffectedPrimaryWorkitems from @doomed where doomed=DefectID
select @error=@@ERROR; if @error<>0 goto ERR
delete DefectVersions from @doomed where doomed=DefectID
select @error=@@ERROR; if @error<>0 goto ERR
delete Defect_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Defect_Now set DuplicateOfID=null from @doomed where doomed=DuplicateOfID
select @error=@@ERROR; if @error<>0 goto ERR
update Defect_Now set VerifiedByID=null from @doomed where doomed=VerifiedByID
select @error=@@ERROR; if @error<>0 goto ERR
update Defect_Now set ResolutionReasonID=null from @doomed where doomed=ResolutionReasonID
select @error=@@ERROR; if @error<>0 goto ERR
update Defect_Now set TypeID=null from @doomed where doomed=TypeID
select @error=@@ERROR; if @error<>0 goto ERR
delete Defect from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Defect set DuplicateOfID=null from @doomed where doomed=DuplicateOfID
select @error=@@ERROR; if @error<>0 goto ERR
update Defect set VerifiedByID=null from @doomed where doomed=VerifiedByID
select @error=@@ERROR; if @error<>0 goto ERR
update Defect set ResolutionReasonID=null from @doomed where doomed=ResolutionReasonID
select @error=@@ERROR; if @error<>0 goto ERR
update Defect set TypeID=null from @doomed where doomed=TypeID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Defects purged', 0, 1, @rowcount) with nowait

raiserror('Stories', 0, 1) with nowait
delete Story_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Story_Now set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update Story_Now set RiskID=null from @doomed where doomed=RiskID
select @error=@@ERROR; if @error<>0 goto ERR
update Story_Now set IdentifiedInID=null from @doomed where doomed=IdentifiedInID
select @error=@@ERROR; if @error<>0 goto ERR
update Story_Now set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
delete Story from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Story set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update Story set RiskID=null from @doomed where doomed=RiskID
select @error=@@ERROR; if @error<>0 goto ERR
update Story set IdentifiedInID=null from @doomed where doomed=IdentifiedInID
select @error=@@ERROR; if @error<>0 goto ERR
update Story set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Stories purged', 0, 1, @rowcount) with nowait

raiserror('Epics', 0, 1) with nowait
delete StrategicThemeEpics from @doomed where doomed=EpicID
select @error=@@ERROR; if @error<>0 goto ERR
delete IssueEpics from @doomed where doomed=EpicID
select @error=@@ERROR; if @error<>0 goto ERR
delete IssueBlockedEpics from @doomed where doomed=EpicID
select @error=@@ERROR; if @error<>0 goto ERR
delete RequestEpics from @doomed where doomed=EpicID
select @error=@@ERROR; if @error<>0 goto ERR
delete Epic_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Epic_Now set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update Epic_Now set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update Epic_Now set PriorityID=null from @doomed where doomed=PriorityID
select @error=@@ERROR; if @error<>0 goto ERR
update Epic_Now set MorphedFromID=null from @doomed where doomed=MorphedFromID
select @error=@@ERROR; if @error<>0 goto ERR
delete Epic from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Epic set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update Epic set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update Epic set PriorityID=null from @doomed where doomed=PriorityID
select @error=@@ERROR; if @error<>0 goto ERR
update Epic set MorphedFromID=null from @doomed where doomed=MorphedFromID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Epics purged', 0, 1, @rowcount) with nowait

raiserror('PrimaryWorkitems', 0, 1) with nowait
delete PrimaryWorkitemDependencies from @doomed where doomed=PrimaryWorkitemID1 or doomed=PrimaryWorkitemID2
select @error=@@ERROR; if @error<>0 goto ERR
delete BuildRunCompletesPrimaryWorkitems from @doomed where doomed=PrimaryWorkitemID
select @error=@@ERROR; if @error<>0 goto ERR
delete ChangeSetPrimaryWorkitems from @doomed where doomed=PrimaryWorkitemID
select @error=@@ERROR; if @error<>0 goto ERR
delete DefectAffectedPrimaryWorkitems from @doomed where doomed=PrimaryWorkitemID
select @error=@@ERROR; if @error<>0 goto ERR
delete IssueBlockedPrimaryWorkitems from @doomed where doomed=PrimaryWorkitemID
select @error=@@ERROR; if @error<>0 goto ERR
delete IssuePrimaryWorkitems from @doomed where doomed=PrimaryWorkitemID
select @error=@@ERROR; if @error<>0 goto ERR
delete RequestPrimaryWorkitems from @doomed where doomed=PrimaryWorkitemID
select @error=@@ERROR; if @error<>0 goto ERR
delete PrimaryWorkitemSplitFromHierarchy from @doomed where doomed=AncestorID or doomed=DescendantID
select @error=@@ERROR; if @error<>0 goto ERR
delete PrimaryWorkitem_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update PrimaryWorkitem_Now set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update PrimaryWorkitem_Now set PriorityID=null from @doomed where doomed=PriorityID
select @error=@@ERROR; if @error<>0 goto ERR
update PrimaryWorkitem_Now set SplitFromID=null from @doomed where doomed=SplitFromID
select @error=@@ERROR; if @error<>0 goto ERR
update PrimaryWorkitem_Now set ClassOfServiceID=null from @doomed where doomed=ClassOfServiceID
select @error=@@ERROR; if @error<>0 goto ERR
update PrimaryWorkitem_Now set DeliveryCategoryID=null from @doomed where doomed=DeliveryCategoryID
select @error=@@ERROR; if @error<>0 goto ERR
delete PrimaryWorkitem from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update PrimaryWorkitem set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update PrimaryWorkitem set PriorityID=null from @doomed where doomed=PriorityID
select @error=@@ERROR; if @error<>0 goto ERR
update PrimaryWorkitem set SplitFromID=null from @doomed where doomed=SplitFromID
select @error=@@ERROR; if @error<>0 goto ERR
update PrimaryWorkitem set ClassOfServiceID=null from @doomed where doomed=ClassOfServiceID
select @error=@@ERROR; if @error<>0 goto ERR
update PrimaryWorkitem set DeliveryCategoryID=null from @doomed where doomed=DeliveryCategoryID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s PrimaryWorkitems purged', 0, 1, @rowcount) with nowait

raiserror('Themes', 0, 1) with nowait
delete Theme_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Theme_Now set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
update Theme_Now set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update Theme_Now set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update Theme_Now set PriorityID=null from @doomed where doomed=PriorityID
select @error=@@ERROR; if @error<>0 goto ERR
update Theme_Now set RiskID=null from @doomed where doomed=RiskID
select @error=@@ERROR; if @error<>0 goto ERR
delete Theme from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Theme set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
update Theme set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update Theme set CategoryID=null from @doomed where doomed=CategoryID
select @error=@@ERROR; if @error<>0 goto ERR
update Theme set PriorityID=null from @doomed where doomed=PriorityID
select @error=@@ERROR; if @error<>0 goto ERR
update Theme set RiskID=null from @doomed where doomed=RiskID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Themes purged', 0, 1, @rowcount) with nowait

raiserror('Workitems', 0, 1) with nowait
delete WorkitemGoals from @doomed where doomed=WorkitemID
select @error=@@ERROR; if @error<>0 goto ERR
delete WorkitemOwners from @doomed where doomed=WorkitemID
select @error=@@ERROR; if @error<>0 goto ERR
delete WorkitemParentHierarchy from @doomed where doomed=AncestorID or doomed=DescendantID
select @error=@@ERROR; if @error<>0 goto ERR
delete WorkitemSuperHierarchy from @doomed where doomed=AncestorID or doomed=DescendantID
select @error=@@ERROR; if @error<>0 goto ERR
delete Workitem_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Workitem_Now set ParentID=null from @doomed where doomed=ParentID
select @error=@@ERROR; if @error<>0 goto ERR
update Workitem_Now set SuperID=null from @doomed where doomed=SuperID
select @error=@@ERROR; if @error<>0 goto ERR
update Workitem_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update Workitem_Now set TimeboxID=null from @doomed where doomed=TimeboxID
select @error=@@ERROR; if @error<>0 goto ERR
delete Workitem from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Workitem set ParentID=null from @doomed where doomed=ParentID
select @error=@@ERROR; if @error<>0 goto ERR
update Workitem set SuperID=null from @doomed where doomed=SuperID
select @error=@@ERROR; if @error<>0 goto ERR
update Workitem set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update Workitem set TimeboxID=null from @doomed where doomed=TimeboxID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Workitems purged', 0, 1, @rowcount) with nowait

raiserror('Timeboxes', 0, 1) with nowait
delete Timebox_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Timebox_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
delete Timebox from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Timebox set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Timeboxes purged', 0, 1, @rowcount) with nowait

raiserror('Milestones', 0, 1) with nowait
delete Milestone_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Milestone from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Milestones purged', 0, 1, @rowcount) with nowait

raiserror('StrategicThemes', 0, 1) with nowait
delete StrategicThemeEpics from @doomed where doomed=StrategicThemeID
select @error=@@ERROR; if @error<>0 goto ERR
delete StrategicTheme_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update StrategicTheme_Now set LevelID=null from @doomed where doomed=LevelID
select @error=@@ERROR; if @error<>0 goto ERR
delete StrategicTheme from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update StrategicTheme set LevelID=null from @doomed where doomed=LevelID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s StrategicThemes purged', 0, 1, @rowcount) with nowait

raiserror('Allocations', 0, 1) with nowait
delete AllocationParentHierarchy from @doomed where doomed=AncestorID or doomed=DescendantID
select @error=@@ERROR; if @error<>0 goto ERR
delete Allocation_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Allocation from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Allocations purged', 0, 1, @rowcount) with nowait

raiserror('Budgets', 0, 1) with nowait
delete Budget_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Budget_Now set ScopeLabelID=null from @doomed where doomed=ScopeLabelID
select @error=@@ERROR; if @error<>0 goto ERR
delete Budget from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Budget set ScopeLabelID=null from @doomed where doomed=ScopeLabelID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Budgets purged', 0, 1, @rowcount) with nowait

raiserror('Roadmaps', 0, 1) with nowait
delete Roadmap_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Roadmap from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Roadmaps purged', 0, 1, @rowcount) with nowait

raiserror('Scopes', 0, 1) with nowait
delete BuildProjectScopes from @doomed where doomed=ScopeID
select @error=@@ERROR; if @error<>0 goto ERR
delete GoalTargetedBy from @doomed where doomed=ScopeID
select @error=@@ERROR; if @error<>0 goto ERR
delete ScopeScopeLabels from @doomed where doomed=ScopeID
select @error=@@ERROR; if @error<>0 goto ERR
delete ScopeMemberACL from @doomed where doomed=ScopeID
select @error=@@ERROR; if @error<>0 goto ERR
delete ScopeParentHierarchy from @doomed where doomed=AncestorID or doomed=DescendantID
select @error=@@ERROR; if @error<>0 goto ERR
delete Scope_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Scope_Now set ParentID=null from @doomed where doomed=ParentID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope_Now set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope_Now set TestSuiteID=null from @doomed where doomed=TestSuiteID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope_Now set ScheduleID=null from @doomed where doomed=ScheduleID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope_Now set SchemeID=null from @doomed where doomed=SchemeID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope_Now set PlanningLevelID=null from @doomed where doomed=PlanningLevelID
select @error=@@ERROR; if @error<>0 goto ERR
delete Scope from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope set ParentID=null from @doomed where doomed=ParentID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope set StatusID=null from @doomed where doomed=StatusID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope set TestSuiteID=null from @doomed where doomed=TestSuiteID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope set ScheduleID=null from @doomed where doomed=ScheduleID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope set SchemeID=null from @doomed where doomed=SchemeID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope set PlanningLevelID=null from @doomed where doomed=PlanningLevelID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Scopes purged', 0, 1, @rowcount) with nowait

raiserror('Schemes', 0, 1) with nowait
delete AttributeDefinitionVisibility from @doomed where doomed=SchemeID
select @error=@@ERROR; if @error<>0 goto ERR
delete SchemeSelectedValues from @doomed where doomed=SchemeID or doomed=ListID
select @error=@@ERROR; if @error<>0 goto ERR
delete Scheme_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Scheme from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Schemes purged', 0, 1, @rowcount) with nowait

raiserror('Schedules', 0, 1) with nowait
delete Schedule_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Schedule from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Schedules purged', 0, 1, @rowcount) with nowait

raiserror('Images', 0, 1) with nowait
delete Image_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete [Image] from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Images purged', 0, 1, @rowcount) with nowait

raiserror('Publications', 0, 1) with nowait
delete PublishedPayload from Publication join @doomed on doomed=Publication.ID where PublishedPayload.ID=Payload
delete Publication_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Publication_Now set AssetID=null from @doomed where doomed=AssetID
select @error=@@ERROR; if @error<>0 goto ERR
delete Publication from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Publication set AssetID=null from @doomed where doomed=AssetID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Publications purged', 0, 1, @rowcount) with nowait

raiserror('Timesheets', 0, 1) with nowait
delete Timesheet_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete [Timesheet] from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Timesheets purged', 0, 1, @rowcount) with nowait

raiserror('Grants', 0, 1) with nowait
delete Grant_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete [Grant] from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Grants purged', 0, 1, @rowcount) with nowait

raiserror('Members', 0, 1) with nowait
delete CommunityFollowers from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete RoomParticipants from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete MemberFollowers from @doomed where doomed=MemberID1 or doomed=MemberID2
select @error=@@ERROR; if @error<>0 goto ERR
delete MemberMemberLabels from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete MessageRecipients from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionTestOwners from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete ScopeMemberACL from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete TeamCapacityExcludedMembers from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete WorkitemOwners from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete ConversationParticipants from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete ExpressionSpaceFollowers from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete Login from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
delete Member_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Member_Now set AvatarID=null from @doomed where doomed=AvatarID
select @error=@@ERROR; if @error<>0 goto ERR
update Member_Now set ManagerID=null from @doomed where doomed=ManagerID
select @error=@@ERROR; if @error<>0 goto ERR
delete Member from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Member set AvatarID=null from @doomed where doomed=AvatarID
select @error=@@ERROR; if @error<>0 goto ERR
update Member set ManagerID=null from @doomed where doomed=ManagerID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Members purged', 0, 1, @rowcount) with nowait

raiserror('List', 0, 1) with nowait
delete List_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete List from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s List values purged', 0, 1, @rowcount) with nowait

raiserror('Teams', 0, 1) with nowait
delete Team_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Team from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Teams purged', 0, 1, @rowcount) with nowait

raiserror('BaseAssets', 0, 1) with nowait
delete ExpressionMentions from @doomed where doomed=BaseAssetID
select @error=@@ERROR; if @error<>0 goto ERR
delete BaseAssetIdeas from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
delete BaseAsset_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete BaseAsset from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s BaseAssets purged', 0, 1, @rowcount) with nowait

raiserror('Rooms', 0, 1) with nowait
delete RoomTopics from @doomed where doomed=RoomID
select @error=@@ERROR; if @error<>0 goto ERR
delete RoomParticipants from @doomed where doomed=RoomID
select @error=@@ERROR; if @error<>0 goto ERR
delete Room_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Room_Now set ScopeLabelID=null from @doomed where doomed=ScopeLabelID
select @error=@@ERROR; if @error<>0 goto ERR
update Room_Now set ScheduleID=null from @doomed where doomed=ScheduleID
select @error=@@ERROR; if @error<>0 goto ERR
update Room_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update Room_Now set MascotID=null from @doomed where doomed=MascotID
select @error=@@ERROR; if @error<>0 goto ERR
update Room_Now set DefaultScopeID=null from @doomed where doomed=DefaultScopeID
select @error=@@ERROR; if @error<>0 goto ERR
delete Room from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Room set ScopeLabelID=null from @doomed where doomed=ScopeLabelID
select @error=@@ERROR; if @error<>0 goto ERR
update Room set ScheduleID=null from @doomed where doomed=ScheduleID
select @error=@@ERROR; if @error<>0 goto ERR
update Room set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update Room set MascotID=null from @doomed where doomed=MascotID
select @error=@@ERROR; if @error<>0 goto ERR
update Room set DefaultScopeID=null from @doomed where doomed=DefaultScopeID
select @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s Rooms purged', 0, 1, @rowcount) with nowait

raiserror('AssetAudits', 0, 1) with nowait
delete AssetAudit from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s AssetAudits purged', 0, 1, @rowcount) with nowait

raiserror('AssetStrings', 0, 1) with nowait
delete AssetString from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s AssetStrings purged', 0, 1, @rowcount) with nowait

raiserror('AssetLongStrings', 0, 1) with nowait
delete AssetLongString from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
raiserror('%s AssetLongStrings purged', 0, 1, @rowcount) with nowait

raiserror('Rebuilding EffectiveACLs', 0, 1) with nowait
insert dbo.EffectiveACL
select ScopeID, MemberID, RoleID, RightsMask = RightsMask | case when Owner<>0 then cast(0x200000000 as bigint) else 0 end
from (
	select DescendantID ScopeID, MemberID, RoleID, Owner, ROW_NUMBER() over (partition by DescendantID, MemberID order by Distance asc) WithinGroup
	from dbo.ScopeParentHierarchy
	join dbo.ScopeMemberACL on ScopeID=AncestorID
	where AuditEnd is null
) X
join dbo.Role_Now on Role_Now.ID=RoleID
where WithinGroup=1 and RightsMask<>0
option(maxdop 1) -- see http://connect.microsoft.com/SQLServer/feedback/details/634433

select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR

if (@commitChanges = 2) goto TX_DONE
if (@commitChanges = 1) begin raiserror('Committing changes...', 0, 1) with nowait; goto OK end
raiserror('Rolling back changes.  To commit changes, pass @commitChanges=1',16,1)
ERR:
if (@commitChanges = 2) goto TX_DONE
rollback tran TX
OK:
commit
TX_DONE:
exec sp_MSforeachtable @command1='enable trigger all on ?'

if (@user_access_desc <> 'SINGLE_USER') begin
	raiserror('Putting database into %s mode', 0, 1, @user_access_desc) with nowait
	declare @sql nvarchar(max) = 'alter database current set ' + @user_access_desc + ' with rollback immediate'
	exec(@sql)
	if (@is_auto_update_stats_async_on = 1) begin
		raiserror('Enabling async auto-update states', 0, 1) with nowait
		alter database current set AUTO_UPDATE_STATISTICS_ASYNC ON
	end
end

DONE:
raiserror('=== Done ===', 0, 1) with nowait
