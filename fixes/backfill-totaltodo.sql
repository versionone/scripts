/*
 * Backfill TotalToDo for all Fact.PrimaryWorkitem tables in a Datamart database.
 * It is also important to backfill the missing entries in the Fact.Workitem table
 *
 *	NOTE:  This script defaults to rolling back changes.
 *		To commit changes, set @saveChanges = 1.
 */
declare @saveChanges bit; --set @saveChanges = 1
declare @error int, @rowcount int
set nocount on; begin tran; save tran TX

UPDATE PrimaryWorkitemTrends set
    TotalDetailEstimate = ISNULL(PrimaryWorkitemTrends.DetailEstimate, 0) + ISNULL(Task.DetailEstimate, 0) + ISNULL(Test.DetailEstimate, 0),
    TotalToDo = CASE WHEN coalesce(PrimaryWorkitemTrends.ToDo, Task.ToDo, Test.ToDo) is not null
    THEN ISNULL(PrimaryWorkitemTrends.ToDo, 0) + ISNULL(Task.ToDo, 0) + ISNULL(Test.ToDo, 0) END
from Fact.PrimaryWorkitem PrimaryWorkitemTrends
    left join (
    select sum(ToDo) as ToDo
    , sum(DetailEstimate) as DetailEstimate
    , DateKey as dk1, PrimaryWorkitemKey as pwk1
    from Fact.Task T
    group by DateKey , PrimaryWorkitemKey
    ) Task
    on Task.dk1=PrimaryWorkitemTrends.DateKey and Task.pwk1=PrimaryWorkitemTrends.WorkitemKey
    left join (
    select sum(ToDo) as ToDo
        , sum(DetailEstimate) as DetailEstimate
        , DateKey as dk2, PrimaryWorkitemKey as pwk2
    from Fact.Test T
    group by DateKey , PrimaryWorkitemKey
        ) Test
    on Test.dk2=PrimaryWorkitemTrends.DateKey and Test.pwk2=PrimaryWorkitemTrends.WorkitemKey
where PrimaryWorkitemTrends.DateKey in (select distinct DateKey
from Fact.PrimaryWorkitem
where TotalDetailEstimate is null)

UPDATE WorkitemTrends set
    TotalDetailEstimate = PrimaryWorkitem.TotalDetailEstimate,
    TotalToDo = PrimaryWorkitem.TotalToDo
from Fact.Workitem WorkitemTrends
join Fact.PrimaryWorkitem PrimaryWorkitem on PrimaryWorkitem.WorkitemKey = WorkitemTrends.WorkitemKey
    and PrimaryWorkitem.DateKey = WorkitemTrends.DateKey
where WorkitemTrends.DateKey in (select distinct DateKey
from Fact.PrimaryWorkitem
where TotalDetailEstimate is null);

select @rowcount=@@ROWCOUNT, @error=@@ERROR
if @error<>0 goto ERR
raiserror('%d TotalToDo backfilled for all', 0, 1, @rowcount) with nowait


if (@saveChanges = 1) begin raiserror('Committing changes', 0, 254); goto OK end
raiserror('To commit changes, set @saveChanges=1',16,254)
ERR: raiserror('Rolling back changes', 0, 255); rollback tran TX
OK: commit
DONE:
