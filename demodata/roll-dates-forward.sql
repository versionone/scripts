-- We should disable triggers before updating Now tables

--Set the days to roll.
DECLARE @days int = 1;
-- Set the date cutoff to the current date minus the days to roll forward, creating a 30 second gap behind now
-- We will slot the changed dates ahead of the cutoff into this gap
-- This is to avoid pushing dates into the future while preserving the order of the dates
DECLARE @datecutoff DATETIME;
DECLARE @offsetFromCurrent DATETIME;
SELECT @offsetFromCurrent = DATEADD(SECOND, -30, GETUTCDATE())
SELECT @datecutoff = DATEADD(DAY, -@days, @offsetFromCurrent);

SET QUOTED_IDENTIFIER ON;

-- compress the dates that would be pushed into the future into the 30 second gap from present
DISABLE TRIGGER ALL ON DATABASE;

DECLARE @dayCursor CURSOR;
DECLARE @millisecondsToAdd int;
SET @millisecondsToAdd = 1;
SET @dayCursor = CURSOR FOR
SELECT ID FROM Audit WHERE ChangeDateUTC >= @datecutoff ORDER BY ID ASC;
OPEN @dayCursor;
DECLARE @auditID int;
FETCH NEXT FROM @dayCursor INTO @auditID;
WHILE @@FETCH_STATUS = 0
BEGIN
    UPDATE Audit SET ChangeDateUTC = DATEADD(MILLISECOND, @millisecondsToAdd, @offsetFromCurrent) WHERE ID = @auditID;
    SET @millisecondsToAdd = @millisecondsToAdd + 1;
    FETCH NEXT FROM @dayCursor INTO @auditID;
END;
CLOSE @dayCursor;
DEALLOCATE @dayCursor;

-- add days to the ChangeDateUTC of all audits older than the cutoff date
-- these dates will be pushed a day forward
UPDATE Audit SET ChangeDateUTC = DATEADD(DAY, @days, ChangeDateUTC) WHERE ChangeDateUTC < @datecutoff;


UPDATE Bundle_Now SET EstimatedDeliveryDateUTC = DATEADD(DAY, @days, EstimatedDeliveryDateUTC);
UPDATE Delivery_Now SET DeliveredOnUTC = DATEADD(DAY, @days, DeliveredOnUTC);
UPDATE Snapshot SET Date = DATEADD(DAY, @days, Date);
UPDATE TestRun SET Date = DATEADD(DAY, @days, Date);
UPDATE Retrospective SET Date = DATEADD(DAY, @days, Date);
UPDATE Topic SET ModifyDateUTC = DATEADD(DAY, @days, ModifyDateUTC);
UPDATE BuildRun SET Date = DATEADD(DAY, @days, Date);
UPDATE ActivityStream SET DateOccurred = DATEADD(DAY, @days, DateOccurred), DateRecorded = DATEADD(DAY, @days, DateRecorded);
UPDATE Milestone SET Date = DATEADD(DAY, @days, Date);
UPDATE Access SET AccessedAt = DATEADD(DAY, @days, AccessedAt);
UPDATE PublishedPayload SET PublishDate = DATEADD(DAY, @days, PublishDate);
UPDATE CustomDate SET Value = DATEADD(DAY, @days, Value);
UPDATE Bundle SET EstimatedDeliveryDateUTC = DATEADD(DAY, @days, EstimatedDeliveryDateUTC);
UPDATE Delivery SET DeliveredOnUTC = DATEADD(DAY, @days, DeliveredOnUTC);
UPDATE Expression SET AuthoredAt = DATEADD(DAY, @days, AuthoredAt);
UPDATE Expression_Now SET AuthoredAt = DATEADD(DAY, @days, AuthoredAt);
UPDATE Budget_Now SET BeginDate = DATEADD(DAY, @days, BeginDate), EndDate = DATEADD(DAY, @days, EndDate);
UPDATE Budget SET BeginDate = DATEADD(DAY, @days, BeginDate), EndDate = DATEADD(DAY, @days, EndDate);
UPDATE Scope_Now SET BeginDate = DATEADD(DAY, @days, BeginDate), EndDate = DATEADD(DAY, @days, EndDate);
UPDATE Timebox_Now SET BeginDate = DATEADD(DAY, @days, BeginDate), EndDate = DATEADD(DAY, @days, EndDate);
UPDATE Scope SET BeginDate = DATEADD(DAY, @days, BeginDate), EndDate = DATEADD(DAY, @days, EndDate);
UPDATE Timesheet_Now SET BeginDate = DATEADD(DAY, @days, BeginDate);
UPDATE Issue_Now SET TargetDate = DATEADD(DAY, @days, TargetDate);
UPDATE Timebox SET BeginDate = DATEADD(DAY, @days, BeginDate), EndDate = DATEADD(DAY, @days, EndDate);
UPDATE Timesheet SET BeginDate = DATEADD(DAY, @days, BeginDate);
UPDATE Issue SET TargetDate = DATEADD(DAY, @days, TargetDate);
UPDATE Epic_Now SET PlannedStart = DATEADD(DAY, @days, PlannedStart), PlannedEnd = DATEADD(DAY, @days, PlannedEnd);
UPDATE Epic SET PlannedStart = DATEADD(DAY, @days, PlannedStart), PlannedEnd = DATEADD(DAY, @days, PlannedEnd);
UPDATE Actual_Now SET Date = DATEADD(DAY, @days, Date);
UPDATE Snapshot_Now SET Date = DATEADD(DAY, @days, Date);
UPDATE Actual SET Date = DATEADD(DAY, @days, Date);
UPDATE TestRun_Now SET Date = DATEADD(DAY, @days, Date);
UPDATE Retrospective_Now SET Date = DATEADD(DAY, @days, Date);
UPDATE Topic_Now SET ModifyDateUTC = DATEADD(DAY, @days, ModifyDateUTC);
UPDATE BuildRun_Now SET Date = DATEADD(DAY, @days, Date);
UPDATE Milestone_Now SET Date = DATEADD(DAY, @days, Date);
UPDATE Access_Now SET AccessedAt = DATEADD(DAY, @days, AccessedAt);

ENABLE TRIGGER ALL ON DATABASE;
