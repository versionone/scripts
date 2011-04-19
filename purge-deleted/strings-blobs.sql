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
insert @strings select ReverseNewQuickValuesFilter from RelationDefinition
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

