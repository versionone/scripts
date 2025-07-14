DECLARE @StartTime DATETIME = '2025-07-01T00:00:00'
DECLARE @EndTime DATETIME = '2025-07-14T23:59:59'
DECLARE @SubscriptionGuid UNIQUEIDENTIFIER = '5d3b7bf7-2b53-422f-89de-8fc251ce808e'

SELECT
    wr.*,
    hs.Value AS HeadersContentType,
    rs.Value AS ResponseContentType,
    CONVERT(VARCHAR(MAX), CONVERT(VARBINARY(MAX), hb.Value)) AS HeadersBlobText,
    CONVERT(VARCHAR(MAX), CONVERT(VARBINARY(MAX), rb.Value)) AS ResponseBlobText
FROM dbo.WebhookReceipt wr
LEFT JOIN dbo.Blob hb ON wr.HeadersId = hb.ID
LEFT JOIN dbo.String hs ON hb.ContentType = hs.ID
LEFT JOIN dbo.Blob rb ON wr.ResponseId = rb.ID
LEFT JOIN dbo.String rs ON rb.ContentType = rs.ID
WHERE wr.TimeStamp BETWEEN @StartTime AND @EndTime
  AND wr.SubscriptionGuid = @SubscriptionGuid