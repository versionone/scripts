-- Query to get the failure rate of webhook dispatches, grouped by SubscriptionGuid, Url, and error Status code.

DECLARE @StartTime DATETIME = '2025-07-01T00:00:00'
DECLARE @EndTime DATETIME = '2025-07-14T23:59:59'

SELECT
    SubscriptionGuid,
    Url,
    COUNT(*) AS TotalDispatches,
    SUM(CASE
            WHEN Status >= 400 AND Status < 500 THEN 1 ELSE 0
        END) AS ClientErrorCount,
    SUM(CASE
            WHEN Status >= 500 AND Status < 600 THEN 1 ELSE 0
        END) AS ServerErrorCount,
    SUM(CASE
            WHEN WasReceived = 0 OR (Status < 200 OR Status >= 300)
            THEN 1 ELSE 0
        END) AS FailedDispatches,
    CAST(SUM(CASE
            WHEN WasReceived = 0 OR (Status < 200 OR Status >= 300)
            THEN 1 ELSE 0
        END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS FailureRatePercent,
    CAST(SUM(CASE
            WHEN Status >= 400 AND Status < 500 THEN 1 ELSE 0
        END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS ClientErrorRatePercent,
    CAST(SUM(CASE
            WHEN Status >= 500 AND Status < 600 THEN 1 ELSE 0
        END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS ServerErrorRatePercent
FROM dbo.WebhookReceipt
WHERE TimeStamp BETWEEN @StartTime AND @EndTime
GROUP BY SubscriptionGuid, Url