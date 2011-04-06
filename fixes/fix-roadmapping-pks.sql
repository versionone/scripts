
alter table dbo.[Roadmapping_Roadmap] add constraint [PK_RoadmappingRoadmap] primary key ([Id])
GO

alter table dbo.[Roadmapping_Swimlane] add constraint [PK_RoadmappingSwimlane] primary key ([Id])
GO

alter table dbo.[Roadmapping_Bucket] add constraint [PK_RoadmappingBucket] primary key ([Id])
GO

alter table dbo.[Roadmapping_Item] add constraint [PK_RoadmappingItem] primary key ([Id])
GO

alter table dbo.[Roadmapping_Location] add constraint [PK_RoadmappingLocation] primary key ([Id])
GO

alter table dbo.[Roadmapping_Timeline] add constraint [PK_RoadmappingTimeline] primary key ([Id])
GO

alter table dbo.[Roadmapping_Link] add constraint [PK_RoadmappingLink] primary key ([Id])
GO

alter table dbo.[Roadmapping_AssetReference] add constraint [PK_RoadmappingAssetReference] primary key ([Id])
GO

alter table dbo.[Roadmapping_JournalEntry] add constraint [PK_RoadmappingJournalEntry] primary key ([Id])
GO


