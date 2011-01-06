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
declare @scopeToPurge int; --set @scopeToPurge = 0
declare @allowRecursion bit; --set @allowRecursion = 1

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

exec sp_MSForEachTable @command1='disable trigger all on ?'

-- Ensure the correct database version
declare @supportedVersion varchar(10); set @supportedVersion = '10.2'
if (@supportedVersion is not null) begin
	if not exists (select * from SystemConfig where Name='Version' and Value like @supportedVersion + '.%') begin
		raiserror('This script can only run on a %s VersionOne database',16,1, @supportedVersion)
		goto ERR
	end
end

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
		raiserror('Scope:%i has %i children, so it cannot be purged.  To allow recursion, set @allowRecursion=1',16,3, @scopeToPurge, @rowcount)
		goto ERR
	end
end

---
--- Rack 'em
---

declare @doomed table(doomed int not null primary key)
declare @safeScopes table(safeScope int not null primary key)
declare @safeMembers table(safeMember int not null primary key)
insert @safeMembers values(20)
declare @safeTeams table(safeTeam int not null primary key)

-- doom the seed Scope
insert @doomed values(@scopeToPurge)

-- doom the current children of doomed Scopes, recursively
while 1=1 begin
	insert @doomed select ID from Scope_Now join @doomed on doomed=ParentID 
	except select doomed from @doomed
	if @@ROWCOUNT=0 break
end

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

-- doom all Schedules except those  ever used by safe Scopes
insert @doomed 
select ID from Schedule_Now 
except 
select distinct ScheduleID from Scope join @safeScopes on safeScope=ID where ScheduleID is not null

-- doom Timeboxes currently belonging to doomed  Schedules
insert @doomed 
select ID from Timebox_Now join @doomed on doomed=ScheduleID

-- current/past owners of safe Timeboxes are safe
insert @safeMembers 
select distinct OwnerID from Timebox where ID not in (select doomed from @doomed) and ScheduleID not in (select doomed from @doomed) and OwnerID is not null
except select safeMember from @safeMembers

-- doom all Schemes except those ever used by safe Scopes
insert @doomed 
select ID from Scheme_Now 
except 
select distinct SchemeID from Scope join @safeScopes on safeScope=ID where SchemeID is not null

-- doom Goals that live in doomed Scopes
insert @doomed 
select ID from Goal_Now join @doomed on doomed=ScopeID

-- doom Issues that live in doomed Scopes
insert @doomed 
select ID from Issue_Now join @doomed on doomed=ScopeID

-- current/past owners of safe Issues are safe
insert @safeMembers 
select distinct OwnerID from Issue join @safeScopes on safeScope=ScopeID where ID not in (select doomed from @doomed) and OwnerID is not null
except select safeMember from @safeMembers

-- current/past teams of safe Issues are safe
insert @safeTeams 
select distinct TeamID from Issue join @safeScopes on safeScope=ScopeID where ID not in (select doomed from @doomed) and TeamID is not null
except select safeTeam from @safeTeams

-- doom Requests that live in doomed Scopes
insert @doomed 
select ID from Request_Now join @doomed on doomed=ScopeID

-- current/past owners of safe Requests are safe
insert @safeMembers 
select distinct OwnerID from Request join @safeScopes on safeScope=ScopeID where ID not in (select doomed from @doomed) and OwnerID is not null
except select safeMember from @safeMembers

-- doom Retrospectives that live in doomed Scopes
insert @doomed 
select ID from Retrospective_Now join @doomed on doomed=ScopeID

-- current/past facilitators of safe Retrospectives are safe
insert @safeMembers 
select distinct FacilitatedByID from Retrospective join @safeScopes on safeScope=ScopeID where ID not in (select doomed from @doomed) and FacilitatedByID is not null
except select safeMember from @safeMembers

-- current/past teams of safe Retrospectives are safe
insert @safeTeams 
select distinct TeamID from Retrospective join @safeScopes on safeScope=ScopeID where ID not in (select doomed from @doomed) and TeamID is not null
except select safeTeam from @safeTeams

-- doom RegressionTests belonging to doomed Scopes
insert @doomed 
select ID from RegressionTest_Now join @doomed on doomed=ScopeID

-- current/past Teams of safe RegressionTests are safe
insert @safeTeams 
select distinct TeamID from RegressionTest join @safeScopes on safeScope=ScopeID where ID not in (select doomed from @doomed) and TeamID is not null
except select safeTeam from @safeTeams

-- current/past owners of safe RegressionTests are safe
insert @safeMembers 
select distinct MemberID from RegressionTestOwners where RegressionTestID not in (select doomed from @doomed)
except select safeMember from @safeMembers

-- doom RegressionPlans belonging to doomed Scopes
insert @doomed 
select ID from RegressionPlan_Now join @doomed on doomed=ScopeID

-- current/past Owners of safe RegressionPlans are safe
insert @safeMembers 
select distinct OwnerID from RegressionPlan join @safeScopes on safeScope=ScopeID where ID not in (select doomed from @doomed) and OwnerID is not null
except select safeMember from @safeMembers

-- doom RegressionSuites belonging to doomed RegressionPlans
insert @doomed 
select ID from RegressionSuite_Now join @doomed on doomed=RegressionPlanID

-- current/past Owners of safe RegressionSuites are safe
insert @safeMembers 
select distinct OwnerID from RegressionSuite where ID not in (select doomed from @doomed) and RegressionPlanID not in (select doomed from @doomed) and OwnerID is not null
except select safeMember from @safeMembers

-- doom Environments belonging to doomed Scopes
insert @doomed 
select ID from Environment_Now join @doomed on doomed=ScopeID

-- doom Workitems that live in doomed Scopes
insert @doomed 
select ID from Workitem_Now join @doomed on doomed=ScopeID

-- current/past teams of safe Workitems are safe
insert @safeTeams 
select distinct TeamID from Workitem join @safeScopes on safeScope=ScopeID where ID not in (select doomed from @doomed) and TeamID is not null
except select safeTeam from @safeTeams

-- current/past owners of safe Workitems are safe
insert @safeMembers 
select distinct MemberID from WorkitemOwners where WorkitemID not in (select doomed from @doomed)
except select safeMember from @safeMembers

-- current/past Customers of safe Themes are safe
insert @safeMembers 
select distinct CustomerID from Theme where ID not in (select doomed from @doomed) and CustomerID is not null
except select safeMember from @safeMembers

-- current/past Customers of safe Stories are safe
insert @safeMembers 
select distinct CustomerID from Story where ID not in (select doomed from @doomed) and CustomerID is not null
except select safeMember from @safeMembers

-- current/past Verifiers of safe Defects are safe
insert @safeMembers 
select distinct VerifiedByID from Defect where ID not in (select doomed from @doomed) and VerifiedByID is not null
except select safeMember from @safeMembers

-- doom TestSets belonging to doomed RegressionSuites
insert @doomed 
select ID from TestSet_Now join @doomed on doomed=RegressionSuiteID
except select doomed from @doomed

-- current/past Customers of safe Tasks are safe
insert @safeMembers 
select distinct CustomerID from Task where ID not in (select doomed from @doomed) and CustomerID is not null
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
select distinct MemberID from Capacity join @safeScopes on safeScope=ScopeID where ID not in (select doomed from @doomed) and TimeboxID not in (select doomed from @doomed) and MemberID is not null
except select safeMember from @safeMembers

-- Teams with safe Capacity are safe
insert @safeTeams
select distinct TeamID from Capacity join @safeScopes on safeScope=ScopeID where ID not in (select doomed from @doomed) and TimeboxID not in (select doomed from @doomed) and TeamID is not null
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
select distinct MemberID from Actual join @safeScopes on safeScope=ScopeID where ID not in (select doomed from @doomed) and TimeboxID not in (select doomed from @doomed) and WorkitemID not in (select doomed from @doomed) and MemberID is not null
except select safeMember from @safeMembers

-- Teams with safe Actuals are safe
insert @safeTeams
select distinct TeamID from Actual join @safeScopes on safeScope=ScopeID where ID not in (select doomed from @doomed) and TimeboxID not in (select doomed from @doomed) and WorkitemID not in (select doomed from @doomed) and TeamID is not null
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
select distinct ScopeLabelID from ScopeScopeLabels join @doomed on doom=ScopeID
except 
select distinct ScopeLabelID from ScopeScopeLabels where ScopeID not in (select doomed from @doomed)

-- doom MemberLabels ever used by doomed Members, except those ever used by safe Members
insert @doomed 
select distinct MemberLabelID from MemberMemberLabels join @doomed on doom=MemberID
except 
select distinct MemberLabelID from MemberMemberLabels where MemberID not in (select doomed from @doomed)

-- doom Subscriptions of doomed Members
insert @doomed select ID from Subscription_Now join @doomed on doomed=SubscriberD
-- doom SubscriptionTerms belonging to doomed Subscriptions
insert @doomed select ID from SubscriptionTerm_Now join @doomed on doomed=SubscriptionID

-- doom Accesses by doomed Members
insert @doomed select ID from Access_Now join @doomed on doomed=ByID

-- doom IdeasUserCaches of doomed Members
insert @doomed select ID from IdeasUserCache_Now join @doomed on doomed=MemberID

-- Snapshots?
insert @doomed select ID from Snapshot_Now join @doomed on doomed=AssetID

-- NEVER purge Scope:0 !
delete @doomed where doomed = 0

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
print @rowcount + ' Audits purged'

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

print 'Snapshots'
delete Snapshot_Now from @doomed where doomed=ID or doomed=AssetID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Snapshot from @doomed where doomed=ID or doomed=AssetID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Snapshots purged'

print 'IdeasUserCache'
delete IdeasUserCache_Now from @doomed where doomed=ID or doomed=MemberID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete IdeasUserCache from @doomed where doomed=ID or doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' IdeasUserCaches purged'

print 'Accesses'
delete Access_Now from @doomed where doomed=ID or doomed=ByID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Access from @doomed where doomed=ID or doomed=ByID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Accesses purged'

print 'Subscriptions'
delete SubscriptionTerm_Now from @doomed where doomed=ID or doomed=SubcriptionID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete SubscriptionTerm from @doomed where doomed=ID or doomed=SubcriptionID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' SubscriptionTerms purged'
delete Subscription_Now from @doomed where doomed=ID or doomed=SubscriberID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Subscription from @doomed where doomed=ID or doomed=SubscriberID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Subscriptions purged'

print 'Labels'
delete DefectVersions from @doomed where doomed=VersionLabelID
select @error=@@ERROR; if @error<>0 goto ERR
delete MemberMemberLabels from @doomed where doomed=MemberLabelID
select @error=@@ERROR; if @error<>0 goto ERR
delete ScopeScopeLabels from @doomed where doomed=ScopeLabelID
select @error=@@ERROR; if @error<>0 goto ERR
delete Label_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Label from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Labels purged'

print 'Notes'
delete Note_Now from @doomed where doomed=ID or doomed=AssetID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Note_Now set InResponseToID=null from @doomed where doomed=InResponseToID
select @error=@@ERROR; if @error<>0 goto ERR
update Note_Now set PersonalToID=null from @doomed where doomed=PersonalToID
select @error=@@ERROR; if @error<>0 goto ERR
delete Note from @doomed where doomed=ID or doomed=AssetID or doomed=InResponseToID or doomed=PersonalToID
select @error=@@ERROR; if @error<>0 goto ERR
update Note set InResponseToID=null from @doomed where doomed=InResponseToID
select @error=@@ERROR; if @error<>0 goto ERR
update Note set PersonalToID=null from @doomed where doomed=PersonalToID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Notes purged'

print 'Links'
delete Link_Now from @doomed where doomed=ID or doomed=AssetID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Link from @doomed where doomed=ID or doomed=AssetID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Links purged'

print 'Attachments'
delete Attachment_Now from @doomed where doomed=ID or doomed=AssetID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Attachment from @doomed where doomed=ID or doomed=AssetID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Attachments purged'

print 'MessageReceipts'
delete MessageReceipt_Now from @doomed where doomed=ID or doomed=RecipientID or doomed=MessageID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete MessageReceipt from @doomed where doomed=ID or doomed=RecipientID or doomed=MessageID
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
delete Actual_Now from @doomed where doomed=ID or doomed=ScopeID or doomed=WorkitemID or doomed=MemberID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Actual_Now set TimeboxID=null from @doomed where doomed=TimeboxID
select @error=@@ERROR; if @error<>0 goto ERR
update Actual_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
delete Actual from @doomed where doomed=ID or doomed=ScopeID or doomed=WorkitemID or doomed=MemberID
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
delete BuildRun_Now from @doomed where doomed=ID or doomed=BuildProjectID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete BuildRun from @doomed where doomed=ID or doomed=BuildProjectID
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
delete Capacity_Now from @doomed where doomed=ID or doomed=ScopeID or doomed=TimeboxID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Capacity_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update Capacity_Now set MemberID=null from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
delete Capacity from @doomed where doomed=ID or doomed=ScopeID or doomed=TimeboxID
select @error=@@ERROR; if @error<>0 goto ERR
update Capacity set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update Capacity set MemberID=null from @doomed where doomed=MemberID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Capacities purged'

print 'TestRuns'
delete TestRun_Now from @doomed where doomed=ID or doomed=TestSuiteID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete TestRun from @doomed where doomed=ID or doomed=TestSuiteID
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
delete RegressionSuite_Now from @doomed where doomed=ID or doomed=RegressionPlanID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update RegressionSuite_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionSuite from @doomed where doomed=ID or doomed=RegressionPlanID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionSuite set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' RegressionSuites purged'

print 'RegressionTests'
delete RegressionSuiteRegressionTests from @doomed where doomed=RegressionTestID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionTestOwners from @doomed where doomed=RegressionTestID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionTest_Now from @doomed where doomed=ID or doomed=ScopeID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest_Now set GeneratedFromID=null from @doomed where doomed=GeneratedFromID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionTest from @doomed where doomed=ID or doomed=ScopeID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionTest set GeneratedFromID=null from @doomed where doomed=GeneratedFromID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' RegressionTests purged'

print 'RegressionPlans'
delete RegressionPlan_Now from @doomed where doomed=ID or doomed=ScopeID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update RegressionPlan_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
delete RegressionPlan from @doomed where doomed=ID or doomed=ScopeID
select @error=@@ERROR; if @error<>0 goto ERR
update RegressionPlan set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' RegressionPlans purged'

print 'Goals'
delete GoalTargetedBy from @doomed where doomed=GoalID
select @error=@@ERROR; if @error<>0 goto ERR
delete WorkitemGoals from @doomed where doomed=GoalID
select @error=@@ERROR; if @error<>0 goto ERR
delete Goal_Now from @doomed where doomed=ID or doomed=ScopeID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Goal from @doomed where doomed=ID or doomed=ScopeID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Goals purged'

print 'Retrospectives'
delete RetrospectiveIssues from @doomed where doomed=RetrospectiveID
select @error=@@ERROR; if @error<>0 goto ERR
delete Retrospective_Now from @doomed where doomed=ID or doomed=ScopeID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Retrospective_Now set FacilitatedByID=null from @doomed where doomed=FacilitatedByID
select @error=@@ERROR; if @error<>0 goto ERR
update Retrospective_Now set TimeboxID=null from @doomed where doomed=TimeboxID
select @error=@@ERROR; if @error<>0 goto ERR
update Retrospective_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
delete Retrospective from @doomed where doomed=ID or doomed=ScopeID
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
delete Request_Now from @doomed where doomed=ID or doomed=ScopeID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Request_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
delete Request from @doomed where doomed=ID or doomed=ScopeID
select @error=@@ERROR; if @error<>0 goto ERR
update Request set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Requests purged'

print 'Issues'
delete IssueBlockedPrimaryWorkitems from @doomed where doomed=IssueID
select @error=@@ERROR; if @error<>0 goto ERR
delete IssuePrimaryWorkitems from @doomed where doomed=IssueID
select @error=@@ERROR; if @error<>0 goto ERR
delete RequestIssues from @doomed where doomed=IssueID
select @error=@@ERROR; if @error<>0 goto ERR
delete RetrospectiveIssues from @doomed where doomed=IssueID
select @error=@@ERROR; if @error<>0 goto ERR
delete Issue_Now from @doomed where doomed=ID or doomed=ScopeID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Issue_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
delete Issue from @doomed where doomed=ID or doomed=ScopeID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
update Issue set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Issues purged'

print 'Task'
delete Task_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Task_Now set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
delete Task from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update Task set CustomerID=null from @doomed where doomed=CustomerID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Tasks purged'

print 'Test'
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
delete Environment_Now from @doomed where doomed=ID or doomed=ScopeID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Environment from @doomed where doomed=ID or doomed=ScopeID
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
delete Workitem_Now from @doomed where doomed=ID or doomed=ScopeID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Workitem_Now set ParentID=null from @doomed where doomed=ParentID
select @error=@@ERROR; if @error<>0 goto ERR
update Workitem_Now set SuperID=null from @doomed where doomed=SuperID
select @error=@@ERROR; if @error<>0 goto ERR
update Workitem_Now set TeamID=null from @doomed where doomed=TeamID
select @error=@@ERROR; if @error<>0 goto ERR
update Workitem_Now set TimeboxID=null from @doomed where doomed=TimeboxID
select @error=@@ERROR; if @error<>0 goto ERR
delete Workitem from @doomed where doomed=ID or doomed=ScopeID
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
delete Timebox_Now from @doomed where doomed=ID or doomed=ScheduleID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Timebox_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
delete Timebox from @doomed where doomed=ID or doomed=ScheduleID
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
delete Scope_Now from @doomed where doomed=ID or doomed=SchemeID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope_Now set ParentID=null from @doomed where doomed=ParentID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update Scope_Now set OwnerID=null from @doomed where doomed=OwnerID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope_Now set TestSuiteID=null from @doomed where doomed=TestSuiteID
select @error=@@ERROR; if @error<>0 goto ERR
update Scope_Now set ScheduleID=null from @doomed where doomed=ScheduleID
select @error=@@ERROR; if @error<>0 goto ERR
delete Scope from @doomed where doomed=ID or doomed=SchemeID
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

print 'Members'
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
delete Login from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
delete Member_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
delete Member from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' Members purged'

print 'BaseAssets'
delete BaseAssetIdeas from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
delete BaseAsset_Now from @doomed where doomed=ID
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
update BaseAsset_Now set SecurityScopeID=null from @doomed where doomed=SecurityScopeID
select @error=@@ERROR; if @error<>0 goto ERR
delete BaseAsset from @doomed where doomed=ID
select @error=@@ERROR; if @error<>0 goto ERR
update BaseAsset set SecurityScopeID=null from @doomed where doomed=SecurityScopeID
select @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' BaseAssets purged'

-- Strings
print 'Deleting strings'
declare @strings table(ID int)
insert @strings select UserAgent from Access
insert @strings select Initializer from AssetType
insert @strings select ListValidValuesFilter from AssetType
insert @strings select NameResolutionAttributes from AssetType
insert @strings select Resolver from AssetType
insert @strings select ContentType from Attachment
insert @strings select Filename from Attachment
insert @strings select Name from Attachment
insert @strings select ChangeComment from Audit
insert @strings select ChangeReason from Audit
insert @strings select Name from BaseAsset
insert @strings select Class from BaseRule
insert @strings select Initializer from BaseRule
insert @strings select Calculation from BaseSyntheticAttributeDefinition
insert @strings select Parameter from BaseSyntheticAttributeDefinition
insert @strings select Reference from BuildProject
insert @strings select Reference from BuildRun
insert @strings select Reference from ChangeSet
insert @strings select Value from CustomText
insert @strings select Environment from Defect
insert @strings select FixedInBuild from Defect
insert @strings select FoundBy from Defect
insert @strings select FoundInBuild from Defect
insert @strings select VersionAffected from Defect
insert @strings select Name from Environment
insert @strings select IdeasRole from IdeasUserCache
insert @strings select OnInsert from InsertUpdateRule
insert @strings select OnUpdate from InsertUpdateRule
insert @strings select IdentifiedBy from Issue
insert @strings select Name from Label
insert @strings select Name from Link
insert @strings select URL from Link
insert @strings select Name from List
insert @strings select Email from Member
insert @strings select Nickname from Member
insert @strings select Phone from Member
insert @strings select Name from Note
insert @strings select Implementation from Operation
insert @strings select Calculation from Override
insert @strings select Parameter from Override
insert @strings select ValidValuesFilter from Override
insert @strings select Reference from RegressionPlan
insert @strings select Reference from RegressionSuite
insert @strings select Reference from RegressionTest
insert @strings select Tags from RegressionTest
insert @strings select NewQuickValuesFilter from RelationDefinition
insert @strings select NewValidValuesFilter from RelationDefinition
insert @strings select QuickValuesFilter from RelationDefinition
insert @strings select ReverseNewValidValuesFilter from RelationDefinition
insert @strings select ReverseNewQuickValidValuesFilter from RelationDefinition
insert @strings select ReverseQuickValuesFilter from RelationDefinition
insert @strings select ReverseValidValuesFilter from RelationDefinition
insert @strings select ValidValuesFilter from RelationDefinition
insert @strings select RequestedBy from Request
insert @strings select Name from Role
insert @strings select Name from Scheme
insert @strings select StoryBoardCycleRanges from Scope
insert @strings select StoryBoardPivotList from Scope
insert @strings select StoryBoardWipLimits from Scope
insert @strings select Name from Snapshot
insert @strings select Name from Subscription
insert @strings select Value from SubscriptionTerm
insert @strings select VersionTested from Test
insert @strings select Reference from TestSuite
delete String where ID not in (select distinct ID from @strings where ID is not NULL)
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' strings deleted'

-- LongStrings
print 'Deleting long strings'
declare @longstrings table(ID int)
insert @longstrings select Description from Attachment
insert @longstrings select Description from BaseAsset
insert @longstrings select Value from CustomLongText
insert @longstrings select Resolution from Defect
insert @longstrings select Resolution from Issue
insert @longstrings select Description from Label
insert @longstrings select Description from List
insert @longstrings select Content from Note
insert @longstrings select ExpectedResults from RegressionTest
insert @longstrings select Inputs from RegressionTest
insert @longstrings select Setup from RegressionTest
insert @longstrings select Steps from RegressionTest
insert @longstrings select Resolution from Request
insert @longstrings select Summary from Retrospective
insert @longstrings select Description from Snapshot
insert @longstrings select Benefits from Story
insert @longstrings select Description from Subscription
insert @longstrings select ActualResults from Test
insert @longstrings select ExpectedResults from Test
insert @longstrings select Inputs from Test
insert @longstrings select Setup from Test
insert @longstrings select Steps from Test
delete LongString where ID not in (select distinct ID from @longstrings where ID is not NULL)
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' long strings deleted'

-- Blobs
print 'Deleting blobs'
delete Blob where ID not in (select distinct Content from Attachment where Content is not NULL)
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR
print @rowcount + ' blobs deleted'


print 'Rebuilding hieararchies'
exec [RebuildLineage]
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR

print 'Rebuilding AssetAudit'
exec [AssetAudit_Rebuild]
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR

print 'Rebuilding AssetString'
exec [AssetString_Populate]
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR

print 'Rebuilding AssetLongString'
exec [AssetLongString_Populate]
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR

print 'Rebuilding EffectiveACLs'
delete dbo.EffectiveACL
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR

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

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
exec sp_MSForEachTable @command1='enable trigger all on ?'
OK: commit
print '=== Done ==='