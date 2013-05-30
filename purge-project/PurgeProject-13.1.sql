/*
 *	Purges all vestiges of a project.
 *
 *	Set @scopeToPurge to the ID of the project to purge.
 *	Set @allowRecursion=1 to purge child projects recursively.
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */

declare @saveChanges bit; --set @saveChanges = 1
declare @scopeToPurge int; --set @scopeToPurge = 54198
declare @allowRecursion bit; --set @allowRecursion = 1

-- Ensure the correct database version
declare @supportedVersion varchar(10); set @supportedVersion = '13.1'
if (@supportedVersion is not null) begin
	if not exists (select * from SystemConfig where Name='Version' and Value like @supportedVersion + '.%') begin
		raiserror('This script can only run on a %s VersionOne database',16,1, @supportedVersion)
		goto DONE
	end
end

exec sp_MSForEachTable @command1='disable trigger all on ?'

declare @error int, @rowcount varchar(20)
set nocount on; begin tran;
save tran TX

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
		raiserror('Scope:%i has %s children, so it cannot be purged.  To allow recursion, set @allowRecursion=1',16,3, @scopeToPurge, @rowcount)
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
select ID from BaseAsset_Now where AssetType='Team'
except select safeTeam from @safeTeams

-- Members assigned to safe Scopes are safe
insert @safeMembers
select distinct MemberID from ScopeMemberACL join @safeScopes on safeScope=ScopeID where RoleID<>0 or Owner<>0
except select safeMember from @safeMembers

-- doom Members assigned to doomed Scopes, except safe Members
insert @doomed
select distinct MemberID from ScopeMemberACL join @doomed on doomed=ScopeID where RoleID<>0 or Owner<>0
except select safeMember from @safeMembers

-- doom BaseAssets that are secured by doomed Scopes
insert @doomed
select ID from BaseAsset_Now join @doomed on doomed=SecurityScopeID
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

-- doom Attachments on doomed assets
insert @doomed
select ID from Attachment_Now join @doomed on doomed=AssetID

-- doom Links on doomed assets
insert @doomed
select ID from Link_Now join @doomed on doomed=AssetID

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

-- doom TeamRooms tied to doomed Scopes or doomed Schedules
insert @doomed
select ID from TeamRoom_Now join @doomed on doomed=ScopeID
union
select ID from TeamRoom_Now join @doomed on doomed=ScheduleID

-- doom avatar Images of doomed Members and mascot Images of doomed TeamRooms
insert @doomed
select AvatarID from Member join @doomed on doomed=ID where AvatarID is not null
union
select MascotID from TeamRoom join @doomed on doomed=ID where MascotID is not null

-- doom Publications of doomed Members
insert @doomed
select ID from Publication_Now join @doomed on doomed=AuthorID

------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------

---
--- Whack 'em
---

print 'IDSource'
delete IDSource from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' IDs purged'

print 'AssetAuditChangedByLast'
delete AssetAuditChangedByLast from @doomed where doomed=ID or doomed=ChangedByID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' AssetAuditChangedByLasts purged'

print 'Audits'
update Audit set ChangedByID=null from @doomed where doomed=ChangedByID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Audits updated'

print 'Custom Attributes'
delete CustomBoolean from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Custom booleans purged'
delete CustomDate from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Custom dates purged'
delete CustomLongText from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Custom longtexts purged'
delete CustomNumeric from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Custom numerics purged'
delete CustomRelation from @doomed where doomed=PrimaryID or doomed=ForeignID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Custom relations purged'
delete CustomText from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Custom texts purged'

print 'Ranks'
delete Rank from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Ranks purged'

delete dbo.EffectiveACL
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR

print 'Snapshots'
delete Snapshot_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Snapshot from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Snapshots purged'

print 'IdeasUserCache'
delete IdeasUserCache_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete IdeasUserCache from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' IdeasUserCaches purged'

print 'Accesses'
delete Access_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Access from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Accesses purged'

print 'Subscriptions'
delete SubscriptionTerm_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete SubscriptionTerm from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' SubscriptionTerms purged'
delete Subscription_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Subscription from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Subscriptions purged'

print 'Labels'
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
print @rowcount + ' Labels purged'

print 'Expressions'
delete ExpressionMentions from @doomed where doomed=ExpressionID
select @error=@@ERROR; if @error<>0 goto ERR
delete ExpressionConversationParticipants from @doomed where doomed=ExpressionID
select @error=@@ERROR; if @error<>0 goto ERR
delete Expression_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Expression_Now set InReplyToID=null from @doomed where doomed=InReplyToID
select @error=@@ERROR; if @error<>0 goto ERR
update Expression_Now set AuthorID=null from @doomed where doomed=AuthorID
select @error=@@ERROR; if @error<>0 goto ERR
update Expression_Now set ConversationID=ID from @doomed where doomed=ConversationID
select @error=@@ERROR; if @error<>0 goto ERR
update Expression_Now set TeamRoomID=ID from @doomed where doomed=TeamRoomID
select @error=@@ERROR; if @error<>0 goto ERR
update Expression_Now set ExpressionSpaceID=ID from @doomed where doomed=ExpressionSpaceID
select @error=@@ERROR; if @error<>0 goto ERR
delete Expression from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Expression set InReplyToID=null from @doomed where doomed=InReplyToID
select @error=@@ERROR; if @error<>0 goto ERR
update Expression set AuthorID=null from @doomed where doomed=AuthorID
select @error=@@ERROR; if @error<>0 goto ERR
update Expression set ConversationID=ID from @doomed where doomed=ConversationID
select @error=@@ERROR; if @error<>0 goto ERR
update Expression set TeamRoomID=ID from @doomed where doomed=TeamRoomID
select @error=@@ERROR; if @error<>0 goto ERR
update Expression set ExpressionSpaceID=ID from @doomed where doomed=ExpressionSpaceID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Expressions purged'

print 'Notes'
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
print @rowcount + ' Notes purged'

print 'Links'
delete Link_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Link from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Links purged'

print 'Attachments'
delete Attachment_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Attachment from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Attachments purged'

print 'MessageReceipts'
delete MessageReceipt_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete MessageReceipt from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' MessageReceipts purged'

print 'Messages'
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
print @rowcount + ' Messages purged'

print 'Actuals'
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
print @rowcount + ' Actuals purged'

print 'BuildRuns'
delete BuildRunChangeSets from @doomed where doomed=BuildRunID
select @error=@@ERROR; if @error<>0 goto ERR
delete BuildRunCompletesPrimaryWorkitems from @doomed where doomed=BuildRunID
select @error=@@ERROR; if @error<>0 goto ERR
delete BuildRunFoundDefects from @doomed where doomed=BuildRunID
select @error=@@ERROR; if @error<>0 goto ERR
delete BuildRun_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete BuildRun from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' BuildRuns purged'

print 'BuildProjects'
delete BuildProjectScopes from @doomed where doomed=BuildProjectID
select @error=@@ERROR; if @error<>0 goto ERR
delete BuildProject_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete BuildProject from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' BuildProjects purged'

print 'ChangeSets'
delete BuildRunChangeSets from @doomed where doomed=ChangeSetID
select @error=@@ERROR; if @error<>0 goto ERR
delete ChangeSetPrimaryWorkitems from @doomed where doomed=ChangeSetID
select @error=@@ERROR; if @error<>0 goto ERR
delete ChangeSet_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete ChangeSet from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' ChangeSets purged'

print 'Capacities'
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
print @rowcount + ' Capacities purged'

print 'TestRuns'
delete TestRun_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete TestRun from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' TestRuns purged'

print 'TestSuite'
delete TestSuite_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete TestSuite from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' TestSuites purged'

print 'RegressionSuite'
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
print @rowcount + ' RegressionSuites purged'

print 'RegressionTests'
delete RegressionSuiteRegressionTests from @doomed where doomed=RegressionTestID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionTestOwners from @doomed where doomed=RegressionTestID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionTest_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest_Now set GeneratedFromID=null from @doomed where doomed=GeneratedFromID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionTest from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest set GeneratedFromID=null from @doomed where doomed=GeneratedFromID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' RegressionTests purged'

print 'RegressionPlans'
delete RegressionPlan_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update RegressionPlan_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionPlan from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionPlan set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' RegressionPlans purged'

print 'Goals'
delete GoalTargetedBy from @doomed where doomed=GoalID
select @error=@@ERROR; if @error<>0 goto ERR
delete WorkitemGoals from @doomed where doomed=GoalID
select @error=@@ERROR; if @error<>0 goto ERR
delete Goal_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Goal from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Goals purged'

print 'Retrospectives'
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
print @rowcount + ' Retrospectives purged'

print 'Requests'
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
delete Request from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Request set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Requests purged'

print 'Issues'
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
update Issue_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
delete Issue from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Issues purged'

print 'Tasks'
delete Task_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Task_Now set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
delete Task from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Task set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Tasks purged'

print 'Tests'
delete Test_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Test_Now set GeneratedFromID=null from @doomed where doomed=GeneratedFromID
select @error=@@ERROR; if @error<>0 goto ERR
delete Test from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Test set GeneratedFromID=null from @doomed where doomed=GeneratedFromID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Tests purged'

print 'TestSets'
delete TestSet_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update TestSet_Now set EnvironmentID=null from @doomed where doomed=EnvironmentID
select @error=@@ERROR; if @error<>0 goto ERR
delete TestSet from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update TestSet set EnvironmentID=null from @doomed where doomed=EnvironmentID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' TestSets purged'

print 'Environments'
delete Environment_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Environment from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Environments purged'

print 'Defects'
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
delete Defect from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Defect set DuplicateOfID=null from @doomed where doomed=DuplicateOfID
select @error=@@ERROR; if @error<>0 goto ERR
update Defect set VerifiedByID=null from @doomed where doomed=VerifiedByID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Defects purged'

print 'Stories'
delete StoryDependencies from @doomed where doomed=StoryID1 or doomed=StoryID2
select @error=@@ERROR; if @error<>0 goto ERR
delete Story_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Story_Now set IdentifiedInID=null from @doomed where doomed=IdentifiedInID
select @error=@@ERROR; if @error<>0 goto ERR
update Story_Now set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
delete Story from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Story set IdentifiedInID=null from @doomed where doomed=IdentifiedInID
select @error=@@ERROR; if @error<>0 goto ERR
update Story set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Stories purged'

print 'Epics'
delete IssueEpics from @doomed where doomed=EpicID
select @error=@@ERROR; if @error<>0 goto ERR
delete IssueBlockedEpics from @doomed where doomed=EpicID
select @error=@@ERROR; if @error<>0 goto ERR
delete RequestEpics from @doomed where doomed=EpicID
select @error=@@ERROR; if @error<>0 goto ERR
delete Epic_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Epic_Now set MorphedFromID=null from @doomed where doomed=MorphedFromID
select @error=@@ERROR; if @error<>0 goto ERR
delete Epic from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Epic set MorphedFromID=null from @doomed where doomed=MorphedFromID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Epics purged'

print 'PrimaryWorkitems'
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
update PrimaryWorkitem_Now set SplitFromID=null from @doomed where doomed=SplitFromID
select @error=@@ERROR; if @error<>0 goto ERR
delete PrimaryWorkitem from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update PrimaryWorkitem set SplitFromID=null from @doomed where doomed=SplitFromID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' PrimaryWorkitems purged'

print 'Themes'
delete Theme_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Theme_Now set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
delete Theme from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Theme set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Themes purged'

print 'Workitems'
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
print @rowcount + ' Workitems purged'

print 'Timeboxes'
delete Timebox_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Timebox_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
delete Timebox from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Timebox set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Timeboxes purged'

print 'Scopes'
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
update Scope_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope_Now set TestSuiteID=null from @doomed where doomed=TestSuiteID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope_Now set ScheduleID=null from @doomed where doomed=ScheduleID
select @error=@@ERROR; if @error<>0 goto ERR
delete Scope from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope set ParentID=null from @doomed where doomed=ParentID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope set TestSuiteID=null from @doomed where doomed=TestSuiteID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope set ScheduleID=null from @doomed where doomed=ScheduleID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Scopes purged'

print 'Schemes'
delete AttributeDefinitionVisibility from @doomed where doomed=SchemeID
select @error=@@ERROR; if @error<>0 goto ERR
delete SchemeSelectedValues from @doomed where doomed=SchemeID
select @error=@@ERROR; if @error<>0 goto ERR
delete Scheme_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Scheme from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Schemes purged'

print 'Schedules'
delete Schedule_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Schedule from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Schedules purged'

print 'Images'
delete Image_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete [Image] from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Images purged'

print 'Publications'
delete PublishedPayload from Publication join @doomed on doomed=Publication.ID where PublishedPayload.ID=Payload
delete Publication_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Publication from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Publications purged'

print 'Members'
delete TeamRoomParticipants from @doomed where doomed=MemberID
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
delete ExpressionConversationParticipants from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete ExpressionSpaceFollowers from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete Login from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
delete Member_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Member_Now set AvatarID=null from @doomed where doomed=AvatarID
select @error=@@ERROR; if @error<>0 goto ERR
delete Member from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Member set AvatarID=null from @doomed where doomed=AvatarID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Members purged'

print 'BaseAssets'
delete ExpressionMentions from @doomed where doomed=BaseAssetID
select @error=@@ERROR; if @error<>0 goto ERR
delete BaseAssetIdeas from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
delete BaseAsset_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete BaseAsset from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' BaseAssets purged'

print 'TeamRooms'
delete TeamRoomParticipants from @doomed where doomed=TeamRoomID
select @error=@@ERROR; if @error<>0 goto ERR
delete TeamRoom_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update TeamRoom_Now set ScopeLabelID=null from @doomed where doomed=ScopeLabelID
select @error=@@ERROR; if @error<>0 goto ERR
update TeamRoom_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update TeamRoom_Now set MascotID=null from @doomed where doomed=MascotID
select @error=@@ERROR; if @error<>0 goto ERR
delete TeamRoom from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update TeamRoom set ScopeLabelID=null from @doomed where doomed=ScopeLabelID
select @error=@@ERROR; if @error<>0 goto ERR
update TeamRoom set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update TeamRoom set MascotID=null from @doomed where doomed=MascotID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' TeamRooms purged'

print 'AssetAudits'
delete AssetAudit from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' AssetAudits purged'

print 'AssetStrings'
delete AssetString from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' AssetStrings purged'

print 'AssetLongStrings'
delete AssetLongString from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' AssetLongStrings purged'

print 'Rebuilding EffectiveACLs'
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

if (@saveChanges = 1) begin print 'Committing changes...'; goto OK end
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK:
commit
exec sp_MSForEachTable @command1='enable trigger all on ?'
DONE:
print '=== Done ==='
