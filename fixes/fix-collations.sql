SET NOCOUNT ON
GO

-- Drop Foreign Keys, Checks, Defaults, Triggers, Views, Functions and Procedures
DECLARE @t table 
(
	ID int NOT NULL, 
	DepID int NOT NULL, 
	XType char(2) NOT NULL, 
	ParentID int,
	Level int NULL, 
	UserID int,
	UNIQUE CLUSTERED (ID,DepID)
)
DECLARE @count int, @level int

-- Object->Object
INSERT @t
SELECT o.id, d.depid, o.xtype, o.parent_obj, NULL, o.uid
FROM
	sysobjects o
	LEFT JOIN (
			SELECT id,depid FROM sysdepends WHERE number=0 -- AND depnumber=0
			UNION
			SELECT id,parent_obj depid FROM sysobjects
		) d ON o.id=d.id AND d.id<>d.depid
WHERE ObjectProperty(o.id, N'IsMSShipped')=0 AND ISNULL(ObjectProperty(o.parent_obj, N'IsMSShipped'),0)=0

-- FK->PK
INSERT @t
SELECT so1.id, so2.id, so1.xtype, so1.parent_obj, NULL, so1.uid
FROM sysobjects so1
LEFT JOIN sysforeignkeys sfk ON sfk.constid=so1.id
LEFT JOIN sysobjects so2 ON so2.parent_obj=sfk.rkeyid AND so2.xtype='PK'
WHERE so1.xtype='F' AND OBJECTPROPERTY(so1.parent_obj, 'IsMSShipped')=0
GROUP BY so1.id, so2.id, so1.xtype, so1.parent_obj, so1.uid

SET @level = 0

UPDATE @t
SET Level = @level
WHERE DepID=0

SET @count = @@ROWCOUNT

WHILE @count > 0 BEGIN
	SET @level = @level + 1

	UPDATE @t
	SET Level = @level
	WHERE DepID IN (SELECT ID FROM @t WHERE Level=@level-1)

	SET @count = @@ROWCOUNT
END

DECLARE @sql nvarchar(4000)
DECLARE c CURSOR local fast_forward FOR
	SELECT
		DropSql = 
			CASE XType
				WHEN 'U' THEN 'DROP TABLE [' + user_name(UserID) + '].[' + OBJECT_NAME(ID) + ']'
				WHEN 'PK' THEN 'ALTER TABLE [' + user_name(UserID) + '].[' + OBJECT_NAME(ParentID) + '] DROP CONSTRAINT [' + OBJECT_NAME(ID) + ']'
				WHEN 'UQ' THEN 'ALTER TABLE [' + user_name(UserID) + '].[' + OBJECT_NAME(ParentID) + '] DROP CONSTRAINT [' + OBJECT_NAME(ID) + ']'
				WHEN 'F' THEN 'ALTER TABLE [' + user_name(UserID) + '].[' + OBJECT_NAME(ParentID) + '] DROP CONSTRAINT [' + OBJECT_NAME(ID) + ']'
				WHEN 'C' THEN 'ALTER TABLE [' + user_name(UserID) + '].[' + OBJECT_NAME(ParentID) + '] DROP CONSTRAINT [' + OBJECT_NAME(ID) + ']'
				WHEN 'D' THEN 'ALTER TABLE [' + user_name(UserID) + '].[' + OBJECT_NAME(ParentID) + '] DROP CONSTRAINT [' + OBJECT_NAME(ID) + ']'
				WHEN 'TR' THEN 'DROP TRIGGER [' + user_name(UserID) + '].[' + OBJECT_NAME(ID) + ']'
				WHEN 'V' THEN 'DROP VIEW [' + user_name(UserID) + '].[' + OBJECT_NAME(ID) + ']'
				WHEN 'FN' THEN 'DROP FUNCTION [' + user_name(UserID) + '].[' + OBJECT_NAME(ID) + ']'
				WHEN 'IF' THEN 'DROP FUNCTION [' + user_name(UserID) + '].[' + OBJECT_NAME(ID) + ']'
				WHEN 'TF' THEN 'DROP FUNCTION [' + user_name(UserID) + '].[' + OBJECT_NAME(ID) + ']'
				WHEN 'P' THEN 'DROP PROC [' + user_name(UserID) + '].[' + OBJECT_NAME(ID) + ']'
				WHEN 'S' THEN 'DROP TABLE [' + user_name(UserID) + '].[' + OBJECT_NAME(ID) + ']'
				WHEN 'X' THEN 'DROP FUNCTION [' + user_name(UserID) + '].[' + OBJECT_NAME(ID) + ']'
			END
	FROM @t
	WHERE XType IN ('PK','F','C','D','TR','V','FN','IF','TF','P') -- not U, UQ, S, X, or index
	GROUP BY XType,ID,ParentID,UserID
	ORDER BY MAX(Level) DESC,ID DESC

OPEN c
WHILE 1=1 BEGIN
	FETCH NEXT FROM c INTO @sql
	IF @@FETCH_STATUS<>0 BREAK
	PRINT @sql
	EXEC(@sql)
END
CLOSE c
DEALLOCATE c
GO

CREATE PROC dbo._SetCollation
(
	@table sysname,
	@column sysname,
	@collation nvarchar(1000)
) AS
	DECLARE @sql nvarchar(1000)
	IF (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' and TABLE_NAME=@table and COLUMN_NAME=@column)<>@collation BEGIN
		DECLARE @datatype nvarchar(1000), @null nvarchar(1000)
		SELECT
			@datatype = DATA_TYPE + case when DATA_TYPE='ntext' then '' else '(' + CAST(CHARACTER_MAXIMUM_LENGTH AS nvarchar(1000)) + ')' end,
			@null = CASE IS_NULLABLE WHEN 'YES' THEN ' null' ELSE ' not null' END
		FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' and TABLE_NAME=@table and COLUMN_NAME=@column
		SET @sql = 'alter table dbo.' + QUOTENAME(@table) + ' alter column ' + QUOTENAME(@column) + ' ' + @datatype + ' collate ' + @collation + @null
	END

	IF @sql IS NOT NULL BEGIN
		PRINT @sql
		EXEC(@sql) 
	END
GO

CREATE PROC dbo._ForceBinaryCollation
(
	@tabledotcolumn nvarchar(1000)
) AS
DECLARE @dot int
SET @dot = CHARINDEX('.', @tabledotcolumn)
IF @dot=0 
	RAISERROR('_ForceBinaryCollation: parameter must be of the form <table>.<column>: ''%s''', 16, 1, @tabledotcolumn)
ELSE BEGIN

	DECLARE @collation nvarchar(1000)
	SELECT @collation='Latin1_General_BIN'

	DECLARE @table sysname, @column sysname
	SELECT @table=LEFT(@tabledotcolumn, @dot-1), @column=RIGHT(@tabledotcolumn, LEN(@tabledotcolumn)-@dot)
	exec dbo._SetCollation @table, @column, @collation
END
GO
	
--SELECT 'exec dbo._ForceBinaryCollation ''' + TABLE_NAME + '.' + COLUMN_NAME + ''''
--FROM INFORMATION_SCHEMA.COLUMNS
--where DATA_TYPE in ('char','varchar') and CHARACTER_MAXIMUM_LENGTH<=100
--GO

exec dbo._SetCollation 'Login','Username','Latin1_General_CI_AS'
exec dbo._SetCollation 'AttributeDefinitionVisibility','AttributeDefinition','Latin1_General_BIN'
exec dbo._SetCollation 'LongString','Value','Latin1_General_CI_AS'
exec dbo._ForceBinaryCollation 'BuildRun_Now.AssetType'
exec dbo._ForceBinaryCollation 'BuildRun.AssetType'
exec dbo._ForceBinaryCollation 'Workitem_Now.AssetType'
exec dbo._ForceBinaryCollation 'BuildProject_Now.AssetType'
exec dbo._ForceBinaryCollation 'Workitem.AssetType'
exec dbo._ForceBinaryCollation 'BuildProject.AssetType'
exec dbo._ForceBinaryCollation 'Timebox_Now.AssetType'
exec dbo._ForceBinaryCollation 'Timebox.AssetType'
exec dbo._ForceBinaryCollation 'BaseSyntheticAttributeDefinition_Now.AssetType'
exec dbo._ForceBinaryCollation 'Theme_Now.AssetType'
exec dbo._ForceBinaryCollation 'BaseSyntheticAttributeDefinition.AssetType'
exec dbo._ForceBinaryCollation 'Theme.AssetType'
exec dbo._ForceBinaryCollation 'BaseRule_Now.AssetType'
exec dbo._ForceBinaryCollation 'BaseRule_Now.Name'
exec dbo._ForceBinaryCollation 'TestSuite_Now.AssetType'
exec dbo._ForceBinaryCollation 'BaseRule.AssetType'
exec dbo._ForceBinaryCollation 'BaseRule.Name'
exec dbo._ForceBinaryCollation 'TestSuite.AssetType'
exec dbo._ForceBinaryCollation 'TestSet_Now.AssetType'
exec dbo._ForceBinaryCollation 'BaseAsset_Now.AssetType'
exec dbo._ForceBinaryCollation 'TestSet.AssetType'
exec dbo._ForceBinaryCollation 'BaseAsset.AssetType'
exec dbo._ForceBinaryCollation 'TestRun_Now.AssetType'
exec dbo._ForceBinaryCollation 'TestRun.AssetType'
exec dbo._ForceBinaryCollation 'AttributeDefinition_Now.AssetType'
exec dbo._ForceBinaryCollation 'AttributeDefinition_Now.Name'
exec dbo._ForceBinaryCollation 'AttributeDefinition_Now.AttributeType'
exec dbo._ForceBinaryCollation 'Test_Now.AssetType'
exec dbo._ForceBinaryCollation 'AttributeDefinition.AssetType'
exec dbo._ForceBinaryCollation 'AttributeDefinition.Name'
exec dbo._ForceBinaryCollation 'AttributeDefinition.AttributeType'
exec dbo._ForceBinaryCollation 'Test.AssetType'
exec dbo._ForceBinaryCollation 'Attachment_Now.AssetType'
exec dbo._ForceBinaryCollation 'Attachment.AssetType'
exec dbo._ForceBinaryCollation 'Task_Now.AssetType'
exec dbo._ForceBinaryCollation 'Task.AssetType'
exec dbo._ForceBinaryCollation 'AssetType_Now.AssetType'
exec dbo._ForceBinaryCollation 'AssetType_Now.Name'
exec dbo._ForceBinaryCollation 'AssetType_Now.ShortNameAttribute'
exec dbo._ForceBinaryCollation 'AssetType_Now.SecurityScopeRelation'
exec dbo._ForceBinaryCollation 'AssetType_Now.NewSecurityScopeRelation'
exec dbo._ForceBinaryCollation 'AssetType_Now.DefaultOrderByAttribute'
exec dbo._ForceBinaryCollation 'AssetType_Now.DefaultHierarchyAttribute'
exec dbo._ForceBinaryCollation 'AssetType_Now.NumberPattern'
exec dbo._ForceBinaryCollation 'AssetType_Now.VisibleToInstigator'
exec dbo._ForceBinaryCollation 'AssetType_Now.SecureViaRelation'
exec dbo._ForceBinaryCollation 'SystemConfig.Name'
exec dbo._ForceBinaryCollation 'AssetType.AssetType'
exec dbo._ForceBinaryCollation 'AssetType.Name'
exec dbo._ForceBinaryCollation 'AssetType.ShortNameAttribute'
exec dbo._ForceBinaryCollation 'AssetType.SecurityScopeRelation'
exec dbo._ForceBinaryCollation 'AssetType.NewSecurityScopeRelation'
exec dbo._ForceBinaryCollation 'AssetType.DefaultOrderByAttribute'
exec dbo._ForceBinaryCollation 'AssetType.DefaultHierarchyAttribute'
exec dbo._ForceBinaryCollation 'AssetType.NumberPattern'
exec dbo._ForceBinaryCollation 'AssetType.VisibleToInstigator'
exec dbo._ForceBinaryCollation 'AssetType.SecureViaRelation'
exec dbo._ForceBinaryCollation 'SubscriptionTerm_Now.AssetType'
exec dbo._ForceBinaryCollation 'SubscriptionTerm_Now.AttributeToken'
exec dbo._ForceBinaryCollation 'AssetString.Definition'
exec dbo._ForceBinaryCollation 'SubscriptionTerm.AssetType'
exec dbo._ForceBinaryCollation 'SubscriptionTerm.AttributeToken'
exec dbo._ForceBinaryCollation 'AssetLongString.Definition'
exec dbo._ForceBinaryCollation 'Subscription_Now.AssetType'
exec dbo._ForceBinaryCollation 'Subscription_Now.EventDefinition'
exec dbo._ForceBinaryCollation 'Subscription.AssetType'
exec dbo._ForceBinaryCollation 'Subscription.EventDefinition'
exec dbo._ForceBinaryCollation 'AssetAuditChangedByLast.AssetType'
exec dbo._ForceBinaryCollation 'Story_Now.AssetType'
exec dbo._ForceBinaryCollation 'AssetAudit.AssetType'
exec dbo._ForceBinaryCollation 'Story.AssetType'
exec dbo._ForceBinaryCollation 'Actual_Now.AssetType'
exec dbo._ForceBinaryCollation 'State_Now.AssetType'
exec dbo._ForceBinaryCollation 'State_Now.Code'
exec dbo._ForceBinaryCollation 'Actual.AssetType'
exec dbo._ForceBinaryCollation 'State.AssetType'
exec dbo._ForceBinaryCollation 'State.Code'
exec dbo._ForceBinaryCollation 'Access_Now.AssetType'
exec dbo._ForceBinaryCollation 'Snapshot_Now.AssetType'
exec dbo._ForceBinaryCollation 'Access.AssetType'
exec dbo._ForceBinaryCollation 'Snapshot.AssetType'
exec dbo._ForceBinaryCollation 'Scope_Now.AssetType'
exec dbo._ForceBinaryCollation 'Scope.AssetType'
exec dbo._ForceBinaryCollation 'Schedule_Now.AssetType'
exec dbo._ForceBinaryCollation 'Schedule_Now.TimeboxLength'
exec dbo._ForceBinaryCollation 'Schedule_Now.TimeboxGap'
exec dbo._ForceBinaryCollation 'Schedule.AssetType'
exec dbo._ForceBinaryCollation 'Schedule.TimeboxLength'
exec dbo._ForceBinaryCollation 'Schedule.TimeboxGap'
exec dbo._ForceBinaryCollation 'Role_Now.AssetType'
exec dbo._ForceBinaryCollation 'Role.AssetType'
exec dbo._ForceBinaryCollation 'Retrospective_Now.AssetType'
exec dbo._ForceBinaryCollation 'Retrospective.AssetType'
exec dbo._ForceBinaryCollation 'RequiredAttributeDefinitions.Token'
exec dbo._ForceBinaryCollation 'Request_Now.AssetType'
exec dbo._ForceBinaryCollation 'Request.AssetType'
exec dbo._ForceBinaryCollation 'RelationDefinition_Now.AssetType'
exec dbo._ForceBinaryCollation 'RelationDefinition_Now.ReverseName'
exec dbo._ForceBinaryCollation 'RelationDefinition.AssetType'
exec dbo._ForceBinaryCollation 'RelationDefinition.ReverseName'
exec dbo._ForceBinaryCollation 'RegressionTest_Now.AssetType'
exec dbo._ForceBinaryCollation 'RegressionTest.AssetType'
exec dbo._ForceBinaryCollation 'RegressionSuite_Now.AssetType'
exec dbo._ForceBinaryCollation 'RegressionSuite.AssetType'
exec dbo._ForceBinaryCollation 'RegressionPlan_Now.AssetType'
exec dbo._ForceBinaryCollation 'RegressionPlan.AssetType'
exec dbo._ForceBinaryCollation 'Rank.Definition'
exec dbo._ForceBinaryCollation 'PrimaryWorkitem_Now.AssetType'
exec dbo._ForceBinaryCollation 'PrimaryWorkitem.AssetType'
exec dbo._ForceBinaryCollation 'PrimaryRelation_Now.AssetType'
exec dbo._ForceBinaryCollation 'PrimaryRelation_Now.Relation'
exec dbo._ForceBinaryCollation 'PrimaryRelation.AssetType'
exec dbo._ForceBinaryCollation 'PrimaryRelation.Relation'
exec dbo._ForceBinaryCollation 'Override_Now.AssetType'
exec dbo._ForceBinaryCollation 'Override_Now.Name'
exec dbo._ForceBinaryCollation 'Override.AssetType'
exec dbo._ForceBinaryCollation 'Override.Name'
exec dbo._ForceBinaryCollation 'Operation_Now.AssetType'
exec dbo._ForceBinaryCollation 'Operation_Now.AssetTypeName'
exec dbo._ForceBinaryCollation 'Operation_Now.Name'
exec dbo._ForceBinaryCollation 'Operation_Now.Validator'
exec dbo._ForceBinaryCollation 'Operation.AssetType'
exec dbo._ForceBinaryCollation 'Operation.AssetTypeName'
exec dbo._ForceBinaryCollation 'Operation.Name'
exec dbo._ForceBinaryCollation 'Operation.Validator'
exec dbo._ForceBinaryCollation 'NumberSource.Code'
exec dbo._ForceBinaryCollation 'Note_Now.AssetType'
exec dbo._ForceBinaryCollation 'Note.AssetType'
exec dbo._ForceBinaryCollation 'MessageReceipt_Now.AssetType'
exec dbo._ForceBinaryCollation 'MessageReceipt.AssetType'
exec dbo._ForceBinaryCollation 'Message_Now.AssetType'
exec dbo._ForceBinaryCollation 'Message.AssetType'
exec dbo._ForceBinaryCollation 'Member_Now.AssetType'
exec dbo._ForceBinaryCollation 'Member.AssetType'
exec dbo._ForceBinaryCollation 'ManyToManyRelationDefinition_Now.AssetType'
exec dbo._ForceBinaryCollation 'ManyToManyRelationDefinition.AssetType'
exec dbo._ForceBinaryCollation 'List_Now.AssetType'
exec dbo._ForceBinaryCollation 'List.AssetType'
exec dbo._ForceBinaryCollation 'Link_Now.AssetType'
exec dbo._ForceBinaryCollation 'Link.AssetType'
exec dbo._ForceBinaryCollation 'Label_Now.AssetType'
exec dbo._ForceBinaryCollation 'Label.AssetType'
exec dbo._ForceBinaryCollation 'Issue_Now.AssetType'
exec dbo._ForceBinaryCollation 'Issue.AssetType'
exec dbo._ForceBinaryCollation 'InsertUpdateRule_Now.AssetType'
exec dbo._ForceBinaryCollation 'InsertUpdateRule.AssetType'
exec dbo._ForceBinaryCollation 'IdeasUserCache_Now.AssetType'
exec dbo._ForceBinaryCollation 'IdeasUserCache.AssetType'
exec dbo._ForceBinaryCollation 'Goal_Now.AssetType'
exec dbo._ForceBinaryCollation 'Goal.AssetType'
exec dbo._ForceBinaryCollation 'ExecuteSecurityCheckAttributeDefinition_Now.AssetType'
exec dbo._ForceBinaryCollation 'ExecuteSecurityCheckAttributeDefinition_Now.Operation'
exec dbo._ForceBinaryCollation 'ExecuteSecurityCheckAttributeDefinition.AssetType'
exec dbo._ForceBinaryCollation 'ExecuteSecurityCheckAttributeDefinition.Operation'
exec dbo._ForceBinaryCollation 'EventDefinition_Now.AssetType'
exec dbo._ForceBinaryCollation 'EventDefinition_Now.Name'
exec dbo._ForceBinaryCollation 'EventDefinition_Now.Trigger'
exec dbo._ForceBinaryCollation 'EventDefinition.AssetType'
exec dbo._ForceBinaryCollation 'EventDefinition.Name'
exec dbo._ForceBinaryCollation 'EventDefinition.Trigger'
exec dbo._ForceBinaryCollation 'Environment_Now.AssetType'
exec dbo._ForceBinaryCollation 'Environment.AssetType'
exec dbo._ForceBinaryCollation 'Defect_Now.AssetType'
exec dbo._ForceBinaryCollation 'Defect.AssetType'
exec dbo._ForceBinaryCollation 'DefaultRule_Now.AssetType'
exec dbo._ForceBinaryCollation 'DefaultRule_Now.AttributeDefinition'
exec dbo._ForceBinaryCollation 'DefaultRule.AssetType'
exec dbo._ForceBinaryCollation 'DefaultRule.AttributeDefinition'
exec dbo._ForceBinaryCollation 'CustomText.Definition'
exec dbo._ForceBinaryCollation 'CustomRelation.Definition'
exec dbo._ForceBinaryCollation 'CustomNumeric.Definition'
exec dbo._ForceBinaryCollation 'CustomLongText.Definition'
exec dbo._ForceBinaryCollation 'CustomDate.Definition'
exec dbo._ForceBinaryCollation 'CustomBoolean.Definition'
exec dbo._ForceBinaryCollation 'ChangeSet_Now.AssetType'
exec dbo._ForceBinaryCollation 'ChangeSet.AssetType'
exec dbo._ForceBinaryCollation 'Capacity_Now.AssetType'
exec dbo._ForceBinaryCollation 'Capacity.AssetType'
exec dbo._ForceBinaryCollation 'Expression_Now.AssetType'
exec dbo._ForceBinaryCollation 'Expression.AssetType'
exec dbo._ForceBinaryCollation 'Image_Now.AssetType'
exec dbo._ForceBinaryCollation 'Image.AssetType'
exec dbo._ForceBinaryCollation 'Scheme_Now.AssetType'
exec dbo._ForceBinaryCollation 'Scheme.AssetType'

GO

DROP PROC dbo._ForceBinaryCollation
