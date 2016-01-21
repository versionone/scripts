/*
 *	Remove duplicate commits that have no changes since a specified datetime stamp
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @supportedVersions varchar(1000); select @supportedVersions='15.*'

-- Ensure the correct database version
BEGIN
	declare @sep char(2); select @sep=', '
	if not exists(select *
		from dbo.SystemConfig
		join (
		select SUBSTRING(@supportedVersions, C.Value+1, CHARINDEX(@sep, @supportedVersions+@sep, C.Value+1)-C.Value-1) as Value
		from dbo.Counter C
		where C.Value < DataLength(@supportedVersions) and SUBSTRING(@sep+@supportedVersions, C.Value+1, DataLength(@sep)) = @sep
		) Version on SystemConfig.Value like REPLACE(Version.Value, '*', '%') and SystemConfig.Name = 'Version'
	) begin
			raiserror('Only supported on version(s) %s',16,1, @supportedVersions)
			goto DONE
	end
END

declare @error int, @rowcount int
set nocount on; begin tran; save tran TX

DELETE FROM ActivityStream
	WHERE
	ActivityStream.ActivityId in (
		SELECT a.ActivityId FROM Commits
			JOIN Activity a
				ON cast(a.Body as varchar(max)) LIKE '%"GUID": "' + convert(nvarchar(50), CommitId) + '"%'
			JOIN ActivityStream stream
				ON a.ActivityId = stream.ActivityId
			WHERE
			BucketId='Meta'
			AND cast(Payload as varchar(max)) LIKE '%"EventType":"Changed"%'
			AND cast(Payload as varchar(max)) LIKE '%"Changes":\[]%' ESCAPE '\'
		)
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d ActivityStream records deleted', 0, 1, @rowcount) with nowait

DELETE FROM Activity
	WHERE
		ActivityId IN (
			SELECT a.ActivityId from Commits
				JOIN Activity a
					ON cast(a.Body as varchar(max)) LIKE '%"GUID": "' + convert(nvarchar(50), CommitId) + '"%'
				WHERE
				BucketId='Meta'
				AND cast(Payload as varchar(max)) LIKE '%"EventType":"Changed"%'
				AND cast(Payload as varchar(max)) LIKE '%"Changes":\[]%' ESCAPE '\'
			)
select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d Activity records deleted', 0, 1, @rowcount) with nowait

DELETE FROM Commits
	WHERE
	BucketId='Meta'
	AND cast(Payload as varchar(max)) LIKE '%"EventType":"Changed"%'
	AND cast(Payload as varchar(max)) LIKE '%"Changes":\[]%' ESCAPE '\';

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d Commit records deleted', 0, 1, @rowcount) with nowait


if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE:
