-- Purge Deleted Assets

set nocount on

begin tran

print('Gathering')

declare @gather_ids table(ID int not null)

--dbo.Label
--dbo.Label_Now
insert @gather_ids select ID from dbo.Label_Now where AssetState=255

--dbo.List
--dbo.List_Now
insert @gather_ids select ID from dbo.List_Now where AssetState=255

--dbo.BaseAsset
--dbo.BaseAsset_Now
insert @gather_ids select ID from dbo.BaseAsset_Now where AssetState=255

--dbo.Attachment
--dbo.Attachment_Now
insert @gather_ids select ID from dbo.Attachment_Now where AssetState=255 or AssetID in (select ID from @gather_ids)

--dbo.Note
--dbo.Note_Now
insert @gather_ids select ID from dbo.Note_Now where AssetState=255 or AssetID in (select ID from @gather_ids) or PersonalToID in (select ID from @gather_ids)

--dbo.Link
--dbo.Link_Now
insert @gather_ids select ID from dbo.Link_Now where AssetState=255 or AssetID in (select ID from @gather_ids)

--dbo.IdeasUserCache
--dbo.IdeasUserCache_Now
insert @gather_ids select ID from dbo.IdeasUserCache_Now where MemberID in (select ID from @gather_ids)

--dbo.Access
--dbo.Access_Now
insert @gather_ids select ID from dbo.Access_Now where ByID in (select ID from @gather_ids)

--dbo.Timebox
--dbo.Timebox_Now
insert @gather_ids select ID from dbo.Timebox_Now where ScheduleID in (select ID from @gather_ids)

--dbo.Scope
--dbo.Scope_Now
while 1=1 begin
	insert @gather_ids select ID from dbo.Scope_Now where Scope_Now.ID not in (select ID from @gather_ids) and Scope_Now.ParentID in (select ID from @gather_ids)
	if @@ROWCOUNT=0 break
end

--dbo.RegressionPlan
--dbo.RegressionPlan_Now
insert @gather_ids select ID from dbo.RegressionPlan_Now where ScopeID in (select ID from @gather_ids)

--dbo.RegressionSuite
--dbo.RegressionSuite_Now
insert @gather_ids select ID from dbo.RegressionSuite_Now where RegressionPlanID in (select ID from @gather_ids)

--dbo.RegressionTest
--dbo.RegressionTest_Now
insert @gather_ids select ID from dbo.RegressionTest_Now where ScopeID in (select ID from @gather_ids)

--dbo.Environment
--dbo.Environment_Now
insert @gather_ids select ID from dbo.Environment_Now where ScopeID in (select ID from @gather_ids)

--dbo.Workitem
--dbo.Workitem_Now
insert @gather_ids select ID from dbo.Workitem_Now where ScopeID in (select ID from @gather_ids)
insert @gather_ids select ID from dbo.Workitem_Now where AssetType in ('Task', 'Test') and ParentID in (select ID from @gather_ids)

--dbo.TestSet
--dbo.TestSet_Now
insert @gather_ids select ID from dbo.TestSet_Now where RegressionSuiteID in (select ID from @gather_ids)

--dbo.Goal
--dbo.Goal_Now
insert @gather_ids select ID from dbo.Goal_Now where ScopeID in (select ID from @gather_ids)

--dbo.Issue
--dbo.Issue_Now
insert @gather_ids select ID from dbo.Issue_Now where ScopeID in (select ID from @gather_ids)

--dbo.Request
--dbo.Request_Now
insert @gather_ids select ID from dbo.Request_Now where ScopeID in (select ID from @gather_ids)

--dbo.Retrospective
--dbo.Retrospective_Now
insert @gather_ids select ID from dbo.Retrospective_Now where ScopeID in (select ID from @gather_ids)

--dbo.TestSuite
--dbo.TestSuite_Now

--dbo.TestRun
--dbo.TestRun_Now
insert @gather_ids select ID from dbo.TestRun_Now where TestSuiteID in (select ID from @gather_ids)

--dbo.Actual
--dbo.Actual_Now
insert @gather_ids select ID from dbo.Actual_Now where WorkitemID in (select ID from @gather_ids) or MemberID in (select ID from @gather_ids) or 	ScopeID in (select ID from @gather_ids)

--dbo.Subscription
--dbo.Subscription_Now
insert @gather_ids select ID from dbo.Subscription_Now where SubscriberID in (select ID from @gather_ids) or AssetState=255

--dbo.SubscriptionTerm
--dbo.SubscriptionTerm_Now
insert @gather_ids select ID from dbo.SubscriptionTerm_Now where SubscriptionID in (select ID from @gather_ids) or AssetState=255

--dbo.MessageReceipt
--dbo.MessageReceipt_Now
insert @gather_ids select ID from dbo.MessageReceipt_Now where RecipientID in (select ID from @gather_ids) or AssetState=255

--dbo.Message
--dbo.Message_Now
insert @gather_ids select ID from dbo.Message_Now where ID not in (select MessageID from dbo.MessageReceipt_Now where ID not in (select ID from @gather_ids))


--dbo.BuildProject
--dbo.BuildProject_Now
--dbo.BuildRun
--dbo.BuildRun_Now
--dbo.BuildRunChangeSets
--dbo.BuildRunCompletesPrimaryWorkitems
--dbo.BuildRunFoundDefects
--dbo.Capacity
--dbo.Capacity_Now
--dbo.ChangeSet
--dbo.ChangeSet_Now
--dbo.ChangeSetPrimaryWorkitems
--dbo.Roadmapping_Bucket
--dbo.Roadmapping_Item
--dbo.Roadmapping_JournalEntry
--dbo.Roadmapping_Link
--dbo.Roadmapping_Location
--dbo.Roadmapping_Roadmap
--dbo.Roadmapping_Swimlane
--dbo.Roadmapping_Timeline


print('Purging')

declare @ids table(ID int not null primary key)
insert @ids select distinct(ID) from @gather_ids
select count(*) [Found Assets] from @ids

--dbo.MessageRecipients
delete dbo.MessageRecipients where MessageID in (select ID from @ids) or MemberID in (select ID from @ids)

--dbo.MessageReceipt
--dbo.MessageReceipt_Now
delete dbo.MessageReceipt where ID in (select ID from @ids)
delete dbo.MessageReceipt_Now where ID in (select ID from @ids)

--dbo.Message
--dbo.Message_Now
delete dbo.Message where ID in (select ID from @ids)
delete dbo.Message_Now where ID in (select ID from @ids)

--dbo.EffectiveACL
delete dbo.EffectiveACL where ScopeID in (select ID from @ids) or MemberID in (select ID from @ids)

--dbo.DefectAffectedPrimaryWorkitems
delete dbo.DefectAffectedPrimaryWorkitems where DefectID in (select ID from @ids) or PrimaryWorkitemID in (select ID from @ids)

--dbo.DefectVersions
delete dbo.DefectVersions where DefectID in (select ID from @ids) or VersionLabelID in (select ID from @ids)

--dbo.GoalTargetedBy
delete dbo.GoalTargetedBy where GoalID in (select ID from @ids) or ScopeID in (select ID from @ids)

--dbo.IssueBlockedPrimaryWorkitems
delete dbo.IssueBlockedPrimaryWorkitems where IssueID in (select ID from @ids) or PrimaryWorkitemID in (select ID from @ids)

--dbo.IssuePrimaryWorkitems
delete dbo.IssuePrimaryWorkitems where IssueID in (select ID from @ids) or PrimaryWorkitemID in (select ID from @ids)

--dbo.MemberMemberLabels
delete dbo.MemberMemberLabels where MemberID in (select ID from @ids) or MemberLabelID in (select ID from @ids)

--dbo.RegressionSuiteRegressionTests
delete dbo.RegressionSuiteRegressionTests where RegressionTestID in (select ID from @ids) or RegressionSuiteID in (select ID from @ids)

--dbo.RegressionTestOwners
delete dbo.RegressionTestOwners where RegressionTestID in (select ID from @ids) or MemberID in (select ID from @ids)

--dbo.RequestIssues
delete dbo.RequestIssues where RequestID in (select ID from @ids) or IssueID in (select ID from @ids)

--dbo.RequestPrimaryWorkitems
delete dbo.RequestPrimaryWorkitems where RequestID in (select ID from @ids) or PrimaryWorkitemID in (select ID from @ids)

--dbo.RetrospectiveIssues
delete dbo.RetrospectiveIssues where RetrospectiveID in (select ID from @ids) or IssueID in (select ID from @ids)

--dbo.ScopeScopeLabels
delete dbo.ScopeScopeLabels where ScopeID in (select ID from @ids) or ScopeLabelID in (select ID from @ids)

--dbo.StoryDependencies
delete dbo.StoryDependencies where StoryID1 in (select ID from @ids) or StoryID2 in (select ID from @ids)

--dbo.TeamCapacityExcludedMembers
delete dbo.TeamCapacityExcludedMembers where TeamID in (select ID from @ids) or MemberID in (select ID from @ids)

--dbo.WorkitemGoals
delete dbo.WorkitemGoals where WorkitemID in (select ID from @ids) or GoalID in (select ID from @ids)

--dbo.WorkitemOwners
delete dbo.WorkitemOwners where WorkitemID in (select ID from @ids) or MemberID in (select ID from @ids)

--dbo.ScopeMemberACL
delete dbo.ScopeMemberACL where ScopeID in (select ID from @ids) or MemberID in (select ID from @ids)

--dbo.SubscriptionTerm
--dbo.SubscriptionTerm_Now
delete dbo.SubscriptionTerm where ID in (select ID from @ids)
delete dbo.SubscriptionTerm_Now where ID in (select ID from @ids)

--dbo.Subscription
--dbo.Subscription_Now
delete dbo.Subscription where ID in (select ID from @ids)
delete dbo.Subscription_Now where ID in (select ID from @ids)

--dbo.Actual
--dbo.Actual_Now
delete dbo.Actual where ID in (select ID from @ids)
delete dbo.Actual_Now where ID in (select ID from @ids)

--dbo.TestRun
--dbo.TestRun_Now
delete dbo.TestRun where ID in (select ID from @ids)
delete dbo.TestRun_Now where ID in (select ID from @ids)

--dbo.TestSuite
--dbo.TestSuite_Now
delete dbo.TestSuite where ID in (select ID from @ids)
delete dbo.TestSuite_Now where ID in (select ID from @ids)

--dbo.Retrospective
--dbo.Retrospective_Now
delete dbo.Retrospective where ID in (select ID from @ids)
delete dbo.Retrospective_Now where ID in (select ID from @ids)

--dbo.Request
--dbo.Request_Now
delete dbo.Request where ID in (select ID from @ids)
delete dbo.Request_Now where ID in (select ID from @ids)

--dbo.Issue
--dbo.Issue_Now
delete dbo.Issue where ID in (select ID from @ids)
delete dbo.Issue_Now where ID in (select ID from @ids)

--dbo.Goal
--dbo.Goal_Now
delete dbo.Goal where ID in (select ID from @ids)
delete dbo.Goal_Now where ID in (select ID from @ids)

--dbo.Test
--dbo.Test_Now
delete dbo.Test where ID in (select ID from @ids)
delete dbo.Test_Now where ID in (select ID from @ids)

--dbo.Task
--dbo.Task_Now
delete dbo.Task where ID in (select ID from @ids)
delete dbo.Task_Now where ID in (select ID from @ids)

--dbo.TestSet
--dbo.TestSet_Now
delete dbo.TestSet where ID in (select ID from @ids)
delete dbo.TestSet_Now where ID in (select ID from @ids)

--dbo.Defect
--dbo.Defect_Now
delete dbo.Defect where ID in (select ID from @ids)
delete dbo.Defect_Now where ID in (select ID from @ids)

--dbo.Story
--dbo.Story_Now
delete dbo.Story where ID in (select ID from @ids)
delete dbo.Story_Now where ID in (select ID from @ids)

--dbo.PrimaryWorkitem
--dbo.PrimaryWorkitem_Now
delete dbo.PrimaryWorkitem where ID in (select ID from @ids)
delete dbo.PrimaryWorkitem_Now where ID in (select ID from @ids)

--dbo.Theme
--dbo.Theme_Now
delete dbo.Theme where ID in (select ID from @ids)
delete dbo.Theme_Now where ID in (select ID from @ids)

--dbo.Workitem
--dbo.Workitem_Now
delete dbo.Workitem where ID in (select ID from @ids)
delete dbo.Workitem_Now where ID in (select ID from @ids)

--dbo.Environment
--dbo.Environment_Now
delete dbo.Environment where ID in (select ID from @ids)
delete dbo.Environment_Now where ID in (select ID from @ids)

--dbo.RegressionTest
--dbo.RegressionTest_Now
delete dbo.RegressionTest where ID in (select ID from @ids)
delete dbo.RegressionTest_Now where ID in (select ID from @ids)

--dbo.RegressionSuite
--dbo.RegressionSuite_Now
delete dbo.RegressionSuite where ID in (select ID from @ids)
delete dbo.RegressionSuite_Now where ID in (select ID from @ids)

--dbo.RegressionPlan
--dbo.RegressionPlan_Now
delete dbo.RegressionPlan where ID in (select ID from @ids)
delete dbo.RegressionPlan_Now where ID in (select ID from @ids)

--dbo.BuildProjectScopes
delete dbo.BuildProjectScopes where ScopeID in (select ID from @ids)

--dbo.Scope
--dbo.Scope_Now
delete dbo.Scope where ID in (select ID from @ids)
delete dbo.Scope_Now where ID in (select ID from @ids)

--dbo.Timebox
--dbo.Timebox_Now
delete dbo.Timebox where ID in (select ID from @ids)
delete dbo.Timebox_Now where ID in (select ID from @ids)

--dbo.Schedule
--dbo.Schedule_Now
delete dbo.Schedule where ID in (select ID from @ids)
delete dbo.Schedule_Now where ID in (select ID from @ids)

--dbo.Access
--dbo.Access_Now
delete dbo.Access where ID in (select ID from @ids)
delete dbo.Access_Now where ID in (select ID from @ids)

--dbo.Login
delete dbo.Login where ID in (select ID from @ids)

--dbo.IdeasUserCache
--dbo.IdeasUserCache_Now
delete dbo.IdeasUserCache where ID in (select ID from @ids)
delete dbo.IdeasUserCache_Now where ID in (select ID from @ids)

--dbo.Member
--dbo.Member_Now
delete dbo.Member where ID in (select ID from @ids)
delete dbo.Member_Now where ID in (select ID from @ids)

--dbo.Link
--dbo.Link_Now
delete dbo.Link where ID in (select ID from @ids)
delete dbo.Link_Now where ID in (select ID from @ids)

--dbo.Note
--dbo.Note_Now
delete dbo.Note where ID in (select ID from @ids)
delete dbo.Note_Now where ID in (select ID from @ids)

--dbo.Attachment
--dbo.Attachment_Now
delete dbo.Attachment where ID in (select ID from @ids)
delete dbo.Attachment_Now where ID in (select ID from @ids)

--dbo.BaseAssetIdeas
delete dbo.BaseAssetIdeas where ID in (select ID from @ids)

--dbo.BaseAsset
--dbo.BaseAsset_Now
delete dbo.BaseAsset where ID in (select ID from @ids)
delete dbo.BaseAsset_Now where ID in (select ID from @ids)

--dbo.List
--dbo.List_Now
delete dbo.List where ID in (select ID from @ids)
delete dbo.List_Now where ID in (select ID from @ids)

--dbo.Label
--dbo.Label_Now
delete dbo.Label where ID in (select ID from @ids)
delete dbo.Label_Now where ID in (select ID from @ids)

--dbo.CustomBoolean
delete dbo.CustomBoolean where ID in (select ID from @ids)

--dbo.CustomDate
delete dbo.CustomDate where ID in (select ID from @ids)

--dbo.CustomLongText
delete dbo.CustomLongText where ID in (select ID from @ids)

--dbo.CustomNumeric
delete dbo.CustomNumeric where ID in (select ID from @ids)

--dbo.CustomRelation
delete dbo.CustomRelation where PrimaryID in (select ID from @ids) or ForeignID in (select ID from @ids)

--dbo.CustomText
delete dbo.CustomText where ID in (select ID from @ids)

--dbo.Rank
delete dbo.Rank where ID in (select ID from @ids)

--dbo.AssetAuditChangedByLast
delete dbo.AssetAuditChangedByLast where ChangedByID in (select ID from @ids) or ID in (select ID from @ids)

--dbo.AssetAudit
delete dbo.AssetAudit where ID in (select ID from @ids)

--dbo.Audit
--update dbo.Audit set ChangedByID=NULL where ChangedByID in (select ID from @ids)

print('Clean up strings')

--dbo.String
declare @strings table(ID int primary key)
insert @strings select ID from dbo.String
delete @strings from (select distinct(ChangeReason) Z from dbo.Audit) X where Z=ID
delete @strings from (select distinct(ChangeComment) Z from dbo.Audit) X where Z=ID
delete @strings from (select distinct(Value) Z from dbo.CustomText) X where Z=ID
delete @strings from (select distinct(Name) Z from dbo.List) X where Z=ID
delete @strings from (select distinct(Name) Z from dbo.Label) X where Z=ID
delete @strings from (select distinct(Name) Z from dbo.BaseAsset) X where Z=ID
delete @strings from (select distinct(Nickname) Z from dbo.Member) X where Z=ID
delete @strings from (select distinct(Email) Z from dbo.Member) X where Z=ID
delete @strings from (select distinct(Phone) Z from dbo.Member) X where Z=ID
delete @strings from (select distinct(StoryBoardPivotList) Z from dbo.Scope) X where Z=ID
delete @strings from (select distinct(StoryBoardWipLimits) Z from dbo.Scope) X where Z=ID
delete @strings from (select distinct(StoryBoardCycleRanges) Z from dbo.Scope) X where Z=ID
delete @strings from (select distinct(IdentifiedBy) Z from dbo.Issue) X where Z=ID
delete @strings from (select distinct(RequestedBy) Z from dbo.Request) X where Z=ID
delete @strings from (select distinct(Reference) Z from dbo.ChangeSet) X where Z=ID
delete @strings from (select distinct(Environment) Z from dbo.Defect) X where Z=ID
delete @strings from (select distinct(FoundInBuild) Z from dbo.Defect) X where Z=ID
delete @strings from (select distinct(FoundBy) Z from dbo.Defect) X where Z=ID
delete @strings from (select distinct(FixedInBuild) Z from dbo.Defect) X where Z=ID
delete @strings from (select distinct(VersionAffected) Z from dbo.Defect) X where Z=ID
delete @strings from (select distinct(VersionTested) Z from dbo.Test) X where Z=ID
delete @strings from (select distinct(Name) Z from dbo.Link) X where Z=ID
delete @strings from (select distinct(URL) Z from dbo.Link) X where Z=ID
delete @strings from (select distinct(Name) Z from dbo.Note) X where Z=ID
delete @strings from (select distinct(Name) Z from dbo.Role) X where Z=ID
delete @strings from (select distinct(Name) Z from dbo.Attachment) X where Z=ID
delete @strings from (select distinct(Filename) Z from dbo.Attachment) X where Z=ID
delete @strings from (select distinct(ContentType) Z from dbo.Attachment) X where Z=ID
delete @strings from (select distinct(Initializer) Z from dbo.AssetType) X where Z=ID
delete @strings from (select distinct(NameResolutionAttributes) Z from dbo.AssetType) X where Z=ID
delete @strings from (select distinct(Resolver) Z from dbo.AssetType) X where Z=ID
delete @strings from (select distinct(ValidValuesFilter) Z from dbo.RelationDefinition) X where Z=ID
delete @strings from (select distinct(NewValidValuesFilter) Z from dbo.RelationDefinition) X where Z=ID
delete @strings from (select distinct(ReverseValidValuesFilter) Z from dbo.RelationDefinition) X where Z=ID
delete @strings from (select distinct(ReverseNewValidValuesFilter) Z from dbo.RelationDefinition) X where Z=ID
delete @strings from (select distinct(QuickValuesFilter) Z from dbo.RelationDefinition) X where Z=ID
delete @strings from (select distinct(NewQuickValuesFilter) Z from dbo.RelationDefinition) X where Z=ID
delete @strings from (select distinct(ReverseQuickValuesFilter) Z from dbo.RelationDefinition) X where Z=ID
delete @strings from (select distinct(Calculation) Z from dbo.BaseSyntheticAttributeDefinition) X where Z=ID
delete @strings from (select distinct(Parameter) Z from dbo.BaseSyntheticAttributeDefinition) X where Z=ID
delete @strings from (select distinct(Class) Z from dbo.BaseRule) X where Z=ID
delete @strings from (select distinct(Initializer) Z from dbo.BaseRule) X where Z=ID
delete @strings from (select distinct(OnInsert) Z from dbo.InsertUpdateRule) X where Z=ID
delete @strings from (select distinct(OnUpdate) Z from dbo.InsertUpdateRule) X where Z=ID
delete @strings from (select distinct(Implementation) Z from dbo.Operation) X where Z=ID
delete @strings from (select distinct(Calculation) Z from dbo.Override) X where Z=ID
delete @strings from (select distinct(Parameter) Z from dbo.Override) X where Z=ID
delete @strings from (select distinct(ValidValuesFilter) Z from dbo.Override) X where Z=ID
delete @strings from (select distinct(Name) Z from dbo.Snapshot) X where Z=ID
delete @strings from (select distinct(Reference) Z from dbo.TestSuite) X where Z=ID
delete @strings from (select distinct(Reference) Z from dbo.BuildProject) X where Z=ID
delete @strings from (select distinct(Reference) Z from dbo.BuildRun) X where Z=ID
delete @strings from (select distinct(Reference) Z from dbo.RegressionPlan) X where Z=ID
delete @strings from (select distinct(Reference) Z from dbo.RegressionSuite) X where Z=ID
delete @strings from (select distinct(Reference) Z from dbo.RegressionTest) X where Z=ID
delete @strings from (select distinct(Tags) Z from dbo.RegressionTest) X where Z=ID
delete @strings from (select distinct(Name) Z from dbo.Environment) X where Z=ID
delete @strings from (select distinct(Name) Z from dbo.Subscription) X where Z=ID
delete @strings from (select distinct(Value) Z from dbo.SubscriptionTerm) X where Z=ID
delete @strings from (select distinct(UserAgent) Z from dbo.Access) X where Z=ID
delete @strings from (select distinct(IdeasRole) Z from dbo.IdeasUserCache) X where Z=ID
delete dbo.String where ID in (select ID from @strings)

--dbo.AssetString
delete dbo.AssetString where ID in (select ID from @ids) or StringID not in (select ID from dbo.String)

--dbo.LongString
declare @longstrings table(ID int primary key)
insert @longstrings select ID from dbo.LongString
delete @longstrings from (select distinct(Value) Z from dbo.CustomLongText) X where Z=ID
delete @longstrings from (select distinct(Description) Z from dbo.List) X where Z=ID
delete @longstrings from (select distinct(Description) Z from dbo.Label) X where Z=ID
delete @longstrings from (select distinct(Description) Z from dbo.BaseAsset) X where Z=ID
delete @longstrings from (select distinct(Benefits) Z from dbo.Story) X where Z=ID
delete @longstrings from (select distinct(Resolution) Z from dbo.Issue) X where Z=ID
delete @longstrings from (select distinct(Resolution) Z from dbo.Request) X where Z=ID
delete @longstrings from (select distinct(Resolution) Z from dbo.Defect) X where Z=ID
delete @longstrings from (select distinct(Setup) Z from dbo.Test) X where Z=ID
delete @longstrings from (select distinct(Inputs) Z from dbo.Test) X where Z=ID
delete @longstrings from (select distinct(Steps) Z from dbo.Test) X where Z=ID
delete @longstrings from (select distinct(ExpectedResults) Z from dbo.Test) X where Z=ID
delete @longstrings from (select distinct(ActualResults) Z from dbo.Test) X where Z=ID
delete @longstrings from (select distinct(Setup) Z from dbo.RegressionTest) X where Z=ID
delete @longstrings from (select distinct(Inputs) Z from dbo.RegressionTest) X where Z=ID
delete @longstrings from (select distinct(Steps) Z from dbo.RegressionTest) X where Z=ID
delete @longstrings from (select distinct(ExpectedResults) Z from dbo.RegressionTest) X where Z=ID
delete @longstrings from (select distinct(Content) Z from dbo.Note) X where Z=ID
delete @longstrings from (select distinct(Description) Z from dbo.Attachment) X where Z=ID
delete @longstrings from (select distinct(Description) Z from dbo.Snapshot) X where Z=ID
delete @longstrings from (select distinct(Summary) Z from dbo.Retrospective) X where Z=ID
delete @longstrings from (select distinct(Description) Z from dbo.Subscription) X where Z=ID
delete dbo.LongString where ID in (select ID from @longstrings)

--dbo.AssetLongString
delete dbo.AssetLongString where ID in (select ID from @ids) or StringID not in (select ID from dbo.LongString)

--dbo.Blob
delete dbo.Blob where ID not in (select Content from dbo.Attachment where Content is not NULL)


print('RebuildLineage')
--exec dbo.RebuildLineage
delete dbo.WorkitemSuperHierarchy where AncestorID in (select ID from @ids) or DescendantID in (select ID from @ids)
delete dbo.WorkitemParentHierarchy where AncestorID in (select ID from @ids) or DescendantID in (select ID from @ids)
delete dbo.ScopeParentHierarchy where AncestorID in (select ID from @ids) or DescendantID in (select ID from @ids)
delete dbo.PrimaryWorkitemSplitFromHierarchy where AncestorID in (select ID from @ids) or DescendantID in (select ID from @ids)
delete dbo.NoteInResponseToHierarchy where AncestorID in (select ID from @ids) or DescendantID in (select ID from @ids)

--print('Rebuild EffectiveACL')
--exec dbo.Security_RebuildEffectiveACL

rollback
--commit 