/*	
 *	Restore Schedules to Projects that were whacked by the D-07459 fix,
 *	as documented in D-07471.
 *	
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @supportedVersions varchar(1000); select @supportedVersions='12.2.4.*, 12.2.5.*, 12.3.3.*, 12.3.4.*'

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

declare @error int, @rowcount varchar(20)
set nocount on; begin tran; save tran TX

alter table Scope_Now disable trigger all
alter table Scope disable trigger all

-- Re-assign missing schedules
-- whacked by D-07459 fix followed by a history-sync

update dbo.Scope_Now set ScheduleID=Y.ScheduleID
from (
	select ScopeID, min(ScheduleID) ScheduleID
	from dbo.Workitem_Now
	join dbo.Timebox_Now on Timebox_Now.ID=Workitem_Now.TimeboxID
	join dbo.BaseAsset_Now on BaseAsset_Now.ID=Workitem_Now.ID
	where AssetState<255
	group by ScopeID
	--order by 1
) Y
where Scope_Now.ID=Y.ScopeID and (Scope_Now.ScheduleID is null or Scope_Now.ScheduleID<>Y.ScheduleID)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' current scope schedules restored'

-- Fix Schedule inconsistency
-- introduced by D-07459 fix

update dbo.Scope set ScheduleID=Y.ScheduleID
from (
	select Scope.ID, Scope.AuditBegin, min(Timebox.ScheduleID) ScheduleID
	from (select
		AuditBegin=case 
			when BaseAsset.AuditBegin<Workitem.AuditBegin then Workitem.AuditBegin 
			else BaseAsset.AuditBegin 
		end,
		AuditEnd=case 
			when BaseAsset.AuditEnd is null then Workitem.AuditEnd 
			when Workitem.AuditEnd<BaseAsset.AuditEnd then Workitem.AuditEnd 
			else BaseAsset.AuditEnd 
		end,
		ScopeID,
		TimeboxID
		from BaseAsset, Workitem
		where
			BaseAsset.ID=Workitem.ID
			and AssetState<255
			and BaseAsset.AuditBegin<isnull(Workitem.AuditEnd, 2147483647) and Workitem.AuditBegin<isnull(BaseAsset.AuditEnd, 2147483647) 
	) W, Scope, Timebox
	where
		Scope.ID=W.ScopeID and Timebox.ID=W.TimeboxID
		and W.AuditBegin<isnull(Scope.AuditEnd, 2147483647) and Scope.AuditBegin<isnull(W.AuditEnd, 2147483647) 
		and Timebox.AuditBegin<isnull(W.AuditEnd, 2147483647) and W.AuditBegin<isnull(Timebox.AuditEnd, 2147483647) 
		and Timebox.AuditBegin<isnull(Scope.AuditEnd, 2147483647) and Scope.AuditBegin<isnull(Timebox.AuditEnd, 2147483647) 
	group by Scope.ID, Scope.AuditBegin
) Y
where Scope.ID=Y.ID and Scope.AuditBegin=Y.AuditBegin and (Scope.ScheduleID is null or Scope.ScheduleID<>Y.ScheduleID)

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
print @rowcount + ' historical scope schedules restored'

if (@saveChanges = 1) goto OK
raiserror('Rolling back changes.  To commit changes, set @saveChanges=1',16,1)
ERR: rollback tran TX
OK: commit

alter table Scope_Now enable trigger all
alter table Scope enable trigger all

DONE: