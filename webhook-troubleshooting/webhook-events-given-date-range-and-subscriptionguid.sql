DECLARE @StartTime DATETIME = '2025-07-01T00:00:00'
DECLARE @EndTime DATETIME = '2025-07-14T23:59:59'
DECLARE @SubscriptionGuid UNIQUEIDENTIFIER = '5d3b7bf7-2b53-422f-89de-8fc251ce808e'

SELECT
    *,
    CAST (Payload AS VARCHAR(MAX)) AS PayloadJsonText
FROM dbo.WebhookEvents
WHERE CommitStamp BETWEEN @StartTime AND @EndTime
  AND SubscriptionGuid = @SubscriptionGuid