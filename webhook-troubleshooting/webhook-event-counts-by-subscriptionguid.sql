DECLARE @StartDate DATETIME = '2025-07-01T00:00:00'
DECLARE @EndDate DATETIME = '2025-07-14T23:59:59'

SELECT
    SubscriptionGuid,
    COUNT(*) AS EventCount,
    MIN(CommitStamp) AS FirstCommitStamp,
    MAX(CommitStamp) AS LastCommitStamp
FROM dbo.WebhookEvents
WHERE CommitStamp BETWEEN @StartDate AND @EndDate
GROUP BY SubscriptionGuid