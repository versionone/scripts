begin tran

alter table AttributeDefinition_Now drop constraint FK_AttributeDefinition_AssetType
alter table EventDefinition_Now drop constraint FK_EventDefinition_AssetType
alter table AssetType_Now drop constraint FK_AssetType_Base

delete Override where ID<0
delete PrimaryRelation where ID<0
delete Operation where ID<0
delete InsertUpdateRule where ID<0
delete DefaultRule where ID<0
delete BaseRule where ID<0
delete ExecuteSecurityCheckAttributeDefinition where ID<0
delete BaseSyntheticAttributeDefinition where ID<0
delete ManyToManyRelationDefinition where ID<0
delete RelationDefinition where ID<0
delete AttributeDefinition where ID<0
delete AssetTypeBaseHierarchy where DescendantID<0
delete AssetType where ID<0

delete Override_Now where ID<0
delete PrimaryRelation_Now where ID<0
delete Operation_Now where ID<0
delete InsertUpdateRule_Now where ID<0
delete DefaultRule_Now where ID<0
delete BaseRule_Now where ID<0
delete ExecuteSecurityCheckAttributeDefinition_Now where ID<0
delete BaseSyntheticAttributeDefinition_Now where ID<0
delete ManyToManyRelationDefinition_Now where ID<0
delete RelationDefinition_Now where ID<0
delete AttributeDefinition_Now where ID<0
delete AssetTypeBaseHierarchy where DescendantID<0
delete AssetType_Now where ID<0

select * from AssetType_Now
select * from AttributeDefinition_Now

rollback
--commit