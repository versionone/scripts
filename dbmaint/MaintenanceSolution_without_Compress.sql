/*

SQL Server Backup, Integrity Check and Index Optimization.

The solution is supported on SQL Server 2005, SQL Server 2008 and SQL Server 2008 R2.

The documentation is available on http://ola.hallengren.com/Documentation.html.

The solution is free. The license is available on http://ola.hallengren.com/License.html.

My e-mail address is ola@hallengren.com. Please feel free to contact me.

Last updated 5 March 2011.

Ola Hallengren
http://ola.hallengren.com

*/

USE V1_DB_Maintence -- <== This is the database that the objects will be created in.

SET NOCOUNT ON

DECLARE @BackupDirectory nvarchar(max)
DECLARE @CreateJobs nvarchar(max)
DECLARE @Version numeric(18,10)
DECLARE @Error int

SET @BackupDirectory = N'J:\Backup' -- <== Change this to your backup directory.

SET @CreateJobs = 'Y' -- <== Should jobs be created, 'Y' or 'N'?

SET @Error = 0

SET @Version = CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)),CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - 1) + '.' + REPLACE(RIGHT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)), LEN(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)))),'.','') AS numeric(18,10))

IF IS_SRVROLEMEMBER('sysadmin') = 0
BEGIN
  RAISERROR('The server role SysAdmin is needed for the installation.',16,1)
  SET @Error = @@ERROR
END

IF @Version < 9
BEGIN
  RAISERROR('The solution is supported on SQL Server 2005, SQL Server 2008 and SQL Server 2008 R2.',16,1)
  SET @Error = @@ERROR
END

IF (SELECT [compatibility_level] FROM sys.databases WHERE database_id = DB_ID()) < 90
BEGIN
  RAISERROR('The database that you are creating the objects in has to be in compatibility_level 90 or 100.',16,1)
  SET @Error = @@ERROR
END

IF OBJECT_ID('tempdb..#Config') IS NOT NULL DROP TABLE #Config

CREATE TABLE #Config ([Name] nvarchar(max),
                      [Value] nvarchar(max))

DECLARE @ErrorLog TABLE (LogDate datetime,
                         ProcessInfo nvarchar(max),
                         ErrorText nvarchar(max))

INSERT INTO @ErrorLog (LogDate, ProcessInfo, ErrorText)
EXECUTE [master].dbo.sp_readerrorlog 0

IF @@ERROR <> 0
BEGIN
  RAISERROR('Error reading from the error log.',16,1)
  SET @Error = @@ERROR
END

INSERT INTO #Config ([Name], [Value])
SELECT 'LogDirectory', REPLACE(REPLACE(ErrorText,'Logging SQL Server messages in file ''',''),'\ERRORLOG''.','')
FROM @ErrorLog
WHERE ErrorText LIKE 'Logging SQL Server messages in file%'

IF @@ERROR <> 0 OR @@ROWCOUNT <> 1
BEGIN
  RAISERROR('The log directory could not be found.',16,1)
  SET @Error = @@ERROR
END

INSERT INTO #Config ([Name], [Value])
VALUES('BackupDirectory', @BackupDirectory)

INSERT INTO #Config ([Name], [Value])
VALUES('Database', DB_NAME(DB_ID()))

INSERT INTO #Config ([Name], [Value])
VALUES('Jobs', @CreateJobs)

INSERT INTO #Config ([Name], [Value])
VALUES('Error', CAST(@Error AS nvarchar))

IF OBJECT_ID('[dbo].[DatabaseBackup]') IS NOT NULL DROP PROCEDURE [dbo].[DatabaseBackup]
IF OBJECT_ID('[dbo].[DatabaseIntegrityCheck]') IS NOT NULL DROP PROCEDURE [dbo].[DatabaseIntegrityCheck]
IF OBJECT_ID('[dbo].[IndexOptimize]') IS NOT NULL DROP PROCEDURE [dbo].[IndexOptimize]
IF OBJECT_ID('[dbo].[CommandExecute]') IS NOT NULL DROP PROCEDURE [dbo].[CommandExecute]
IF OBJECT_ID('[dbo].[DatabaseSelect]') IS NOT NULL DROP FUNCTION [dbo].[DatabaseSelect]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[DatabaseSelect] (@DatabaseList nvarchar(max))

RETURNS @Database TABLE (DatabaseName nvarchar(max) NOT NULL)

AS

BEGIN

  ----------------------------------------------------------------------------------------------------
  --// Declare variables                                                                          //--
  ----------------------------------------------------------------------------------------------------

  DECLARE @DatabaseItem nvarchar(max)
  DECLARE @Position int

  DECLARE @CurrentID int
  DECLARE @CurrentDatabaseName nvarchar(max)
  DECLARE @CurrentDatabaseStatus bit

  DECLARE @Database01 TABLE (DatabaseName nvarchar(max))

  DECLARE @Database02 TABLE (ID int IDENTITY PRIMARY KEY,
                             DatabaseName nvarchar(max),
                             DatabaseStatus bit,
                             Completed bit)

  DECLARE @Database03 TABLE (DatabaseName nvarchar(max),
                             DatabaseStatus bit)

  DECLARE @Sysdatabases TABLE (DatabaseName nvarchar(max))

  ----------------------------------------------------------------------------------------------------
  --// Split input string into elements                                                           //--
  ----------------------------------------------------------------------------------------------------

  SET @DatabaseList = REPLACE(REPLACE(REPLACE(REPLACE(@DatabaseList,'[',''),']',''),'''',''),'"','')

  WHILE CHARINDEX(',,',@DatabaseList) > 0 SET @DatabaseList = REPLACE(@DatabaseList,',,',',')
  WHILE CHARINDEX(', ',@DatabaseList) > 0 SET @DatabaseList = REPLACE(@DatabaseList,', ',',')
  WHILE CHARINDEX(' ,',@DatabaseList) > 0 SET @DatabaseList = REPLACE(@DatabaseList,' ,',',')

  IF RIGHT(@DatabaseList,1) = ',' SET @DatabaseList = LEFT(@DatabaseList,LEN(@DatabaseList) - 1)
  IF LEFT(@DatabaseList,1) = ','  SET @DatabaseList = RIGHT(@DatabaseList,LEN(@DatabaseList) - 1)

  SET @DatabaseList = LTRIM(RTRIM(@DatabaseList))

  WHILE LEN(@DatabaseList) > 0
  BEGIN
    SET @Position = CHARINDEX(',', @DatabaseList)
    IF @Position = 0
    BEGIN
      SET @DatabaseItem = @DatabaseList
      SET @DatabaseList = ''
    END
    ELSE
    BEGIN
      SET @DatabaseItem = LEFT(@DatabaseList, @Position - 1)
      SET @DatabaseList = RIGHT(@DatabaseList, LEN(@DatabaseList) - @Position)
    END
    IF @DatabaseItem <> '-' INSERT INTO @Database01 (DatabaseName) VALUES(@DatabaseItem)
  END

  ----------------------------------------------------------------------------------------------------
  --// Handle database exclusions                                                                 //--
  ----------------------------------------------------------------------------------------------------

  INSERT INTO @Database02 (DatabaseName, DatabaseStatus, Completed)
  SELECT DISTINCT DatabaseName = CASE WHEN DatabaseName LIKE '-%' THEN RIGHT(DatabaseName,LEN(DatabaseName) - 1) ELSE DatabaseName END,
                  DatabaseStatus = CASE WHEN DatabaseName LIKE '-%' THEN 0 ELSE 1 END,
                  0 AS Completed
  FROM @Database01

  ----------------------------------------------------------------------------------------------------
  --// Resolve elements                                                                           //--
  ----------------------------------------------------------------------------------------------------

  WHILE EXISTS (SELECT * FROM @Database02 WHERE Completed = 0)
  BEGIN

    SELECT TOP 1 @CurrentID = ID,
                 @CurrentDatabaseName = DatabaseName,
                 @CurrentDatabaseStatus = DatabaseStatus
    FROM @Database02
    WHERE Completed = 0
    ORDER BY ID ASC

    IF @CurrentDatabaseName = 'SYSTEM_DATABASES'
    BEGIN
      INSERT INTO @Database03 (DatabaseName, DatabaseStatus)
      SELECT [name], @CurrentDatabaseStatus
      FROM sys.databases
      WHERE database_id <= 4
    END
    ELSE IF @CurrentDatabaseName = 'USER_DATABASES'
    BEGIN
      INSERT INTO @Database03 (DatabaseName, DatabaseStatus)
      SELECT [name], @CurrentDatabaseStatus
      FROM sys.databases
      WHERE database_id > 4
    END
    ELSE IF @CurrentDatabaseName = 'ALL_DATABASES'
    BEGIN
      INSERT INTO @Database03 (DatabaseName, DatabaseStatus)
      SELECT [name], @CurrentDatabaseStatus
      FROM sys.databases
    END
    ELSE IF CHARINDEX('%',@CurrentDatabaseName) > 0
    BEGIN
      INSERT INTO @Database03 (DatabaseName, DatabaseStatus)
      SELECT [name], @CurrentDatabaseStatus
      FROM sys.databases
      WHERE [name] LIKE REPLACE(@CurrentDatabaseName,'_','[_]')
    END
    ELSE
    BEGIN
      INSERT INTO @Database03 (DatabaseName, DatabaseStatus)
      SELECT [name], @CurrentDatabaseStatus
      FROM sys.databases
      WHERE [name] = @CurrentDatabaseName
    END

    UPDATE @Database02
    SET Completed = 1
    WHERE ID = @CurrentID

    SET @CurrentID = NULL
    SET @CurrentDatabaseName = NULL
    SET @CurrentDatabaseStatus = NULL

  END

  ----------------------------------------------------------------------------------------------------
  --// Handle tempdb and database snapshots                                                       //--
  ----------------------------------------------------------------------------------------------------

  INSERT INTO @Sysdatabases (DatabaseName)
  SELECT [name]
  FROM sys.databases
  WHERE [name] <> 'tempdb'
  AND source_database_id IS NULL

  ----------------------------------------------------------------------------------------------------
  --// Return results                                                                             //--
  ----------------------------------------------------------------------------------------------------

  INSERT INTO @Database (DatabaseName)
  SELECT DatabaseName
  FROM @Sysdatabases
  INTERSECT
  SELECT DatabaseName
  FROM @Database03
  WHERE DatabaseStatus = 1
  EXCEPT
  SELECT DatabaseName
  FROM @Database03
  WHERE DatabaseStatus = 0

  RETURN

  ----------------------------------------------------------------------------------------------------

END
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[CommandExecute]

@Command nvarchar(max),
@Comment nvarchar(max),
@Mode int,
@Execute nvarchar(max)

AS

BEGIN

  ----------------------------------------------------------------------------------------------------
  --// Set options                                                                                //--
  ----------------------------------------------------------------------------------------------------

  SET NOCOUNT ON

  SET LOCK_TIMEOUT 3600000

  ----------------------------------------------------------------------------------------------------
  --// Declare variables                                                                          //--
  ----------------------------------------------------------------------------------------------------

  DECLARE @StartMessage nvarchar(max)
  DECLARE @EndMessage nvarchar(max)
  DECLARE @ErrorMessage nvarchar(max)

  DECLARE @StartTime datetime
  DECLARE @EndTime datetime

  DECLARE @Error int

  SET @Error = 0

  ----------------------------------------------------------------------------------------------------
  --// Check input parameters                                                                     //--
  ----------------------------------------------------------------------------------------------------

  IF @Command IS NULL OR @Command = ''
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Command is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Comment IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Comment is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Mode NOT IN(1,2) OR @Mode IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Mode is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Execute NOT IN('Y','N') OR @Execute IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Execute is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Check error variable                                                                       //--
  ----------------------------------------------------------------------------------------------------

  IF @Error <> 0 GOTO ReturnCode

  ----------------------------------------------------------------------------------------------------
  --// Log initial information                                                                    //--
  ----------------------------------------------------------------------------------------------------

  SET @StartTime = CONVERT(datetime,CONVERT(nvarchar,GETDATE(),120),120)

  SET @StartMessage = 'DateTime: ' + CONVERT(nvarchar,@StartTime,120) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Command: ' + @Command
  IF @Comment <> '' SET @StartMessage = @StartMessage + CHAR(13) + CHAR(10) + 'Comment: ' + @Comment
  SET @StartMessage = REPLACE(@StartMessage,'%','%%')
  RAISERROR(@StartMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------
  --// Execute command                                                                            //--
  ----------------------------------------------------------------------------------------------------

  IF @Mode = 1 AND @Execute = 'Y'
  BEGIN
    EXECUTE(@Command)
    SET @Error = @@ERROR
  END

  IF @Mode = 2 AND @Execute = 'Y'
  BEGIN
    BEGIN TRY
      EXECUTE(@Command)
    END TRY
    BEGIN CATCH
      SET @Error = ERROR_NUMBER()
      SET @ErrorMessage = 'Msg ' + CAST(ERROR_NUMBER() AS nvarchar) + ', ' + ISNULL(ERROR_MESSAGE(),'')
      RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    END CATCH
  END

  ----------------------------------------------------------------------------------------------------
  --// Log completing information                                                                 //--
  ----------------------------------------------------------------------------------------------------

  SET @EndTime = CONVERT(datetime,CONVERT(varchar,GETDATE(),120),120)

  SET @EndMessage = 'Outcome: ' + CASE WHEN @Execute = 'N' THEN 'Not Executed' WHEN @Error = 0 THEN 'Succeeded' ELSE 'Failed' END + CHAR(13) + CHAR(10)
  SET @EndMessage = @EndMessage + 'Duration: ' + CASE WHEN DATEDIFF(ss,@StartTime, @EndTime)/(24*3600) > 0 THEN CAST(DATEDIFF(ss,@StartTime, @EndTime)/(24*3600) AS nvarchar) + '.' ELSE '' END + CONVERT(nvarchar,@EndTime - @StartTime,108) + CHAR(13) + CHAR(10)
  SET @EndMessage = @EndMessage + 'DateTime: ' + CONVERT(nvarchar,@EndTime,120) + CHAR(13) + CHAR(10)
  SET @EndMessage = REPLACE(@EndMessage,'%','%%')
  RAISERROR(@EndMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------
  --// Return code                                                                                //--
  ----------------------------------------------------------------------------------------------------

  ReturnCode:

  RETURN @Error

  ----------------------------------------------------------------------------------------------------

END
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[DatabaseBackup]

@Databases nvarchar(max),
@Directory nvarchar(max) = NULL,
@BackupType nvarchar(max),
@Verify nvarchar(max) = 'N',
@CleanupTime int = NULL,
@Compress nvarchar(max) = NULL,
@CopyOnly nvarchar(max) = 'N',
@ChangeBackupType nvarchar(max) = 'N',
@BackupSoftware nvarchar(max) = NULL,
@CheckSum nvarchar(max) = 'N',
@BlockSize int = NULL,
@BufferCount int = NULL,
@MaxTransferSize int = NULL,
@NumberOfFiles int = 1,
@CompressionLevel int = NULL,
@Description nvarchar(max) = NULL,
@Threads int = NULL,
@Throttle int = NULL,
@Execute nvarchar(max) = 'Y'

AS

BEGIN

  ----------------------------------------------------------------------------------------------------
  --// Set options                                                                                //--
  ----------------------------------------------------------------------------------------------------

  SET NOCOUNT ON

  ----------------------------------------------------------------------------------------------------
  --// Declare variables                                                                          //--
  ----------------------------------------------------------------------------------------------------

  DECLARE @StartMessage nvarchar(max)
  DECLARE @EndMessage nvarchar(max)
  DECLARE @DatabaseMessage nvarchar(max)
  DECLARE @ErrorMessage nvarchar(max)

  DECLARE @Version numeric(18,10)

  DECLARE @DefaultDirectory nvarchar(4000)

  DECLARE @CurrentID int
  DECLARE @CurrentDatabase nvarchar(max)
  DECLARE @CurrentBackupType nvarchar(max)
  DECLARE @CurrentFileExtension nvarchar(max)
  DECLARE @CurrentFileNumber int
  DECLARE @CurrentDifferentialLSN numeric(25,0)
  DECLARE @CurrentLogLSN numeric(25,0)
  DECLARE @CurrentLatestBackup datetime
  DECLARE @CurrentDatabaseFS nvarchar(max)
  DECLARE @CurrentDirectory nvarchar(max)
  DECLARE @CurrentFilePath nvarchar(max)
  DECLARE @CurrentDate datetime
  DECLARE @CurrentCleanupDate datetime
  DECLARE @CurrentIsDatabaseAccessible bit
  DECLARE @CurrentMirroringRole nvarchar(max)

  DECLARE @CurrentCommand01 nvarchar(max)
  DECLARE @CurrentCommand02 nvarchar(max)
  DECLARE @CurrentCommand03 nvarchar(max)
  DECLARE @CurrentCommand04 nvarchar(max)

  DECLARE @CurrentCommandOutput01 int
  DECLARE @CurrentCommandOutput02 int
  DECLARE @CurrentCommandOutput03 int
  DECLARE @CurrentCommandOutput04 int

  DECLARE @DirectoryInfoCommand nvarchar(max)

  DECLARE @DirectoryInfo TABLE (FileExists bit,
                                FileIsADirectory bit,
                                ParentDirectoryExists bit)

  DECLARE @tmpDatabases TABLE (ID int IDENTITY PRIMARY KEY,
                               DatabaseName nvarchar(max),
                               Completed bit)

  DECLARE @CurrentFiles TABLE (CurrentFilePath nvarchar(max))

  DECLARE @Error int

  SET @Error = 0

  SET @Version = CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)),CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - 1) + '.' + REPLACE(RIGHT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)), LEN(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)))),'.','') AS numeric(18,10))

  ----------------------------------------------------------------------------------------------------
  --// Log initial information                                                                    //--
  ----------------------------------------------------------------------------------------------------

  SET @StartMessage = 'DateTime: ' + CONVERT(nvarchar,GETDATE(),120) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Server: ' + CAST(SERVERPROPERTY('ServerName') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Version: ' + CAST(SERVERPROPERTY('ProductVersion') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Edition: ' + CAST(SERVERPROPERTY('Edition') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Procedure: ' + QUOTENAME(DB_NAME(DB_ID())) + '.' + (SELECT QUOTENAME(sys.schemas.name) FROM sys.schemas INNER JOIN sys.objects ON sys.schemas.[schema_id] = sys.objects.[schema_id] WHERE [object_id] = @@PROCID) + '.' + QUOTENAME(OBJECT_NAME(@@PROCID)) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Parameters: @Databases = ' + ISNULL('''' + REPLACE(@Databases,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @Directory = ' + ISNULL('''' + REPLACE(@Directory,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @BackupType = ' + ISNULL('''' + REPLACE(@BackupType,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @Verify = ' + ISNULL('''' + REPLACE(@Verify,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @CleanupTime = ' + ISNULL(CAST(@CleanupTime AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @Compress = ' + ISNULL('''' + REPLACE(@Compress,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @CopyOnly = ' + ISNULL('''' + REPLACE(@CopyOnly,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @ChangeBackupType = ' + ISNULL('''' + REPLACE(@ChangeBackupType,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @BackupSoftware = ' + ISNULL('''' + REPLACE(@BackupSoftware,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @CheckSum = ' + ISNULL('''' + REPLACE(@CheckSum,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @BlockSize = ' + ISNULL(CAST(@BlockSize AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @BufferCount = ' + ISNULL(CAST(@BufferCount AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @MaxTransferSize = ' + ISNULL(CAST(@MaxTransferSize AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @NumberOfFiles = ' + ISNULL(CAST(@NumberOfFiles AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @CompressionLevel = ' + ISNULL(CAST(@CompressionLevel AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @Description = ' + ISNULL('''' + REPLACE(@Description,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @Threads = ' + ISNULL(CAST(@Threads AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @Throttle = ' + ISNULL(CAST(@Throttle AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @Execute = ' + ISNULL('''' + REPLACE(@Execute,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + CHAR(13) + CHAR(10)
  SET @StartMessage = REPLACE(@StartMessage,'%','%%')
  RAISERROR(@StartMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------
  --// Select databases                                                                           //--
  ----------------------------------------------------------------------------------------------------

  IF @Databases IS NULL OR @Databases = ''
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Databases is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  INSERT INTO @tmpDatabases (DatabaseName, Completed)
  SELECT DatabaseName AS DatabaseName,
         0 AS Completed
  FROM dbo.DatabaseSelect (@Databases)
  ORDER BY DatabaseName ASC

  IF @@ERROR <> 0 OR (@@ROWCOUNT = 0 AND @Databases <> 'USER_DATABASES')
  BEGIN
    SET @ErrorMessage = 'Error selecting databases.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  SET @ErrorMessage = ''
  SELECT @ErrorMessage = @ErrorMessage + QUOTENAME(DatabaseName) + ', '
  FROM @tmpDatabases
  WHERE REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(DatabaseName,'\',''),'/',''),':',''),'*',''),'?',''),'"',''),'<',''),'>',''),'|',''),' ','') = ''
  ORDER BY DatabaseName ASC
  IF @@ROWCOUNT > 0
  BEGIN
    SET @ErrorMessage = 'The names of the following databases are not supported; ' + LEFT(@ErrorMessage,LEN(@ErrorMessage)-1) + '.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  SET @ErrorMessage = '';
  WITH tmpDatabasesCTE
  AS
  (
  SELECT name AS DatabaseName,
         UPPER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(name,'\',''),'/',''),':',''),'*',''),'?',''),'"',''),'<',''),'>',''),'|',''),' ','')) AS DatabaseNameFS
  FROM sys.databases
  )
  SELECT @ErrorMessage = @ErrorMessage + QUOTENAME(DatabaseName) + ', '
  FROM tmpDatabasesCTE
  WHERE DatabaseNameFS IN(SELECT DatabaseNameFS FROM tmpDatabasesCTE GROUP BY DatabaseNameFS HAVING COUNT(*) > 1)
  AND DatabaseNameFS IN(SELECT UPPER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(DatabaseName COLLATE DATABASE_DEFAULT,'\',''),'/',''),':',''),'*',''),'?',''),'"',''),'<',''),'>',''),'|',''),' ','')) FROM @tmpDatabases)
  AND DatabaseNameFS <> ''
  ORDER BY DatabaseNameFS ASC, DatabaseName ASC
  IF @@ROWCOUNT > 0
  BEGIN
    SET @ErrorMessage = 'The names of the following databases are not unique in the file system; ' + LEFT(@ErrorMessage,LEN(@ErrorMessage)-1) + '.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Get default backup directory                                                               //--
  ----------------------------------------------------------------------------------------------------

  IF @Directory IS NULL
  BEGIN
    EXECUTE [master].dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\MSSQLServer', N'BackupDirectory', @DefaultDirectory OUTPUT
    SET @Directory = @DefaultDirectory
  END

  ----------------------------------------------------------------------------------------------------
  --// Get default compression                                                                    //--
  ----------------------------------------------------------------------------------------------------

  IF @Compress IS NULL
  BEGIN
    SELECT @Compress = CASE
    WHEN @BackupSoftware IS NULL AND EXISTS(SELECT * FROM sys.configurations WHERE name = 'backup compression default' AND value_in_use = 1) THEN 'Y'
    WHEN @BackupSoftware IS NULL AND NOT EXISTS(SELECT * FROM sys.configurations WHERE name = 'backup compression default' AND value_in_use = 1) THEN 'N'
    WHEN @BackupSoftware IS NOT NULL AND (@CompressionLevel IS NULL OR @CompressionLevel > 0)  THEN 'Y'
    WHEN @BackupSoftware IS NOT NULL AND @CompressionLevel = 0  THEN 'N'
    END
  END

  ----------------------------------------------------------------------------------------------------
  --// Check directory                                                                            //--
  ----------------------------------------------------------------------------------------------------

  IF NOT (@Directory LIKE '_:' OR @Directory LIKE '_:\%' OR @Directory LIKE '\\%\%') OR @Directory IS NULL OR LEFT(@Directory,1) = ' ' OR RIGHT(@Directory,1) = ' '
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Directory is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  SET @DirectoryInfoCommand = 'EXECUTE xp_fileexist N''' + REPLACE(@Directory,'''','''''') + ''''

  INSERT INTO @DirectoryInfo (FileExists, FileIsADirectory, ParentDirectoryExists)
  EXECUTE(@DirectoryInfoCommand)

  IF NOT EXISTS (SELECT * FROM @DirectoryInfo WHERE FileExists = 0 AND FileIsADirectory = 1 AND ParentDirectoryExists = 1)
  BEGIN
    SET @ErrorMessage = 'The directory does not exist.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Check input parameters                                                                     //--
  ----------------------------------------------------------------------------------------------------

  IF @BackupType NOT IN ('FULL','DIFF','LOG') OR @BackupType IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @BackupType is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Verify NOT IN ('Y','N') OR @Verify IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Verify is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @CleanupTime < 0 OR (@CleanupTime IS NOT NULL AND @CopyOnly = 'Y')
  BEGIN
    SET @ErrorMessage = 'The value for parameter @CleanupTime is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Compress NOT IN ('Y','N') OR @Compress IS NULL OR (@Compress = 'Y' AND @BackupSoftware IS NULL AND NOT ((@Version >= 10 AND @Version < 10.5 AND SERVERPROPERTY('EngineEdition') = 3) OR (@Version >= 10.5 AND (SERVERPROPERTY('EngineEdition') = 3 OR SERVERPROPERTY('EditionID') = -1534726760)))) OR (@Compress = 'N' AND @BackupSoftware IS NOT NULL AND (@CompressionLevel IS NULL OR @CompressionLevel >= 1)) OR (@Compress = 'Y' AND @BackupSoftware IS NOT NULL AND @CompressionLevel = 0)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Compress is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Compress = 'Y' AND @BackupSoftware IS NULL AND NOT ((@Version >= 10 AND @Version < 10.5 AND SERVERPROPERTY('EngineEdition') = 3) OR (@Version >= 10.5 AND (SERVERPROPERTY('EngineEdition') = 3 OR SERVERPROPERTY('EditionID') = -1534726760)))
  BEGIN
    SET @ErrorMessage = 'Backup compression is only supported in SQL Server 2008 Enterprise and Developer Edition and in SQL Server 2008 R2 Standard, Enterprise, Developer and Datacenter Edition.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @CopyOnly NOT IN ('Y','N') OR @CopyOnly IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @CopyOnly is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @ChangeBackupType NOT IN ('Y','N') OR @ChangeBackupType IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @ChangeBackupType is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @BackupSoftware NOT IN ('LITESPEED','SQLBACKUP','HYPERBAC','SQLSAFE')
  BEGIN
    SET @ErrorMessage = 'The value for parameter @BackupSoftware is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @BackupSoftware = 'LITESPEED' AND NOT EXISTS (SELECT * FROM [master].sys.objects WHERE [type] = 'X' AND [name] = 'xp_backup_database')
  BEGIN
    SET @ErrorMessage = 'LiteSpeed is not installed.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @BackupSoftware = 'SQLBACKUP' AND NOT EXISTS (SELECT * FROM [master].sys.objects WHERE [type] = 'X' AND [name] = 'sqlbackup')
  BEGIN
    SET @ErrorMessage = 'SQLBackup is not installed.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @BackupSoftware = 'SQLSAFE' AND NOT EXISTS (SELECT * FROM [master].sys.objects WHERE [type] = 'X' AND [name] = 'xp_ss_backup')
  BEGIN
    SET @ErrorMessage = 'SQLsafe is not installed.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @CheckSum NOT IN ('Y','N') OR @CheckSum IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @CheckSum is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @BlockSize NOT IN (512,1024,2048,4096,8192,16384,32768,65536) OR (@BlockSize IS NOT NULL AND @BackupSoftware = 'SQLBACKUP') OR (@BlockSize IS NOT NULL AND @BackupSoftware = 'SQLSAFE')
  BEGIN
    SET @ErrorMessage = 'The value for parameter @BlockSize is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @BufferCount <= 0 OR @BufferCount > 2147483647 OR (@BufferCount IS NOT NULL AND @BackupSoftware = 'SQLBACKUP') OR (@BufferCount IS NOT NULL AND @BackupSoftware = 'SQLSAFE')
  BEGIN
    SET @ErrorMessage = 'The value for parameter @BufferCount is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @MaxTransferSize < 65536 OR @MaxTransferSize > 4194304 OR @MaxTransferSize % 65536 > 0 OR (@MaxTransferSize IS NOT NULL AND @BackupSoftware = 'SQLBACKUP') OR (@MaxTransferSize IS NOT NULL AND @BackupSoftware = 'SQLSAFE')
  BEGIN
    SET @ErrorMessage = 'The value for parameter @MaxTransferSize is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @NumberOfFiles < 1 OR @NumberOfFiles > 64 OR (@NumberOfFiles > 32 AND @BackupSoftware = 'SQLBACKUP') OR @NumberOfFiles IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @NumberOfFiles is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF (@BackupSoftware IS NULL AND @CompressionLevel IS NOT NULL) OR (@BackupSoftware = 'HYPERBAC' AND @CompressionLevel IS NOT NULL) OR (@BackupSoftware = 'LITESPEED' AND (@CompressionLevel < 0 OR @CompressionLevel > 10)) OR (@BackupSoftware = 'SQLBACKUP' AND (@CompressionLevel < 0 OR @CompressionLevel > 4)) OR (@BackupSoftware = 'SQLSAFE' AND (@CompressionLevel < 1 OR @CompressionLevel > 4))
  BEGIN
    SET @ErrorMessage = 'The value for parameter @CompressionLevel is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF LEN(@Description) > 255 OR (@BackupSoftware = 'LITESPEED' AND LEN(@Description) > 128)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Description is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Threads IS NOT NULL AND (@BackupSoftware NOT IN('LITESPEED','SQLBACKUP','SQLSAFE') OR @BackupSoftware IS NULL) OR @Threads < 2 OR @Threads > 32
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Threads is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Throttle IS NOT NULL AND (@BackupSoftware NOT IN('LITESPEED') OR @BackupSoftware IS NULL) OR @Throttle < 1 OR @Throttle > 100
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Throttle is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Execute NOT IN('Y','N') OR @Execute IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Execute is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Check error variable                                                                       //--
  ----------------------------------------------------------------------------------------------------

  IF @Error <> 0 GOTO Logging

  ----------------------------------------------------------------------------------------------------
  --// Execute backup commands                                                                    //--
  ----------------------------------------------------------------------------------------------------

  WHILE EXISTS (SELECT * FROM @tmpDatabases WHERE Completed = 0)
  BEGIN

    SELECT TOP 1 @CurrentID = ID,
                 @CurrentDatabase = DatabaseName
    FROM @tmpDatabases
    WHERE Completed = 0
    ORDER BY ID ASC

    IF EXISTS (SELECT * FROM sys.database_recovery_status WHERE database_id = DB_ID(@CurrentDatabase) AND database_guid IS NOT NULL)
    BEGIN
      SET @CurrentIsDatabaseAccessible = 1
    END
    ELSE
    BEGIN
      SET @CurrentIsDatabaseAccessible = 0
    END

    SELECT @CurrentMirroringRole = mirroring_role_desc
    FROM sys.database_mirroring
    WHERE database_id = DB_ID(@CurrentDatabase)

    SELECT @CurrentDifferentialLSN = differential_base_lsn
    FROM sys.master_files
    WHERE database_id = DB_ID(@CurrentDatabase)
    AND [type] = 0
    AND [file_id] = 1

    -- Workaround for a bug in SQL Server 2005
    IF @Version >= 9 AND @Version < 10
    AND (SELECT differential_base_lsn FROM sys.master_files WHERE database_id = DB_ID(@CurrentDatabase) AND [type] = 0 AND [file_id] = 1) = (SELECT differential_base_lsn FROM sys.master_files WHERE database_id = DB_ID('model') AND [type] = 0 AND [file_id] = 1)
    AND (SELECT differential_base_guid FROM sys.master_files WHERE database_id = DB_ID(@CurrentDatabase) AND [type] = 0 AND [file_id] = 1) = (SELECT differential_base_guid FROM sys.master_files WHERE database_id = DB_ID('model') AND [type] = 0 AND [file_id] = 1)
    AND (SELECT differential_base_time FROM sys.master_files WHERE database_id = DB_ID(@CurrentDatabase) AND [type] = 0 AND [file_id] = 1) IS NULL
    BEGIN
      SET @CurrentDifferentialLSN = NULL
    END

    -- If a VSS snapshot has been taken since the last full backup, a differential backup cannot be performed
    IF EXISTS (SELECT * FROM msdb.dbo.backupset WHERE database_name = @CurrentDatabase AND [type] = 'D' AND is_snapshot = 1 AND checkpoint_lsn = @CurrentDifferentialLSN)
    BEGIN
      SET @CurrentDifferentialLSN = NULL
    END

    SELECT @CurrentLogLSN = last_log_backup_lsn
    FROM sys.database_recovery_status
    WHERE database_id = DB_ID(@CurrentDatabase)

    SET @CurrentBackupType = @BackupType

    IF @ChangeBackupType = 'Y'
    BEGIN
      IF @CurrentBackupType = 'LOG' AND DATABASEPROPERTYEX(@CurrentDatabase,'Recovery') <> 'SIMPLE' AND @CurrentLogLSN IS NULL AND @CurrentDatabase <> 'master'
      BEGIN
        SET @CurrentBackupType = 'DIFF'
      END
      IF @CurrentBackupType = 'DIFF' AND @CurrentDifferentialLSN IS NULL AND @CurrentDatabase <> 'master'
      BEGIN
        SET @CurrentBackupType = 'FULL'
      END
    END

    SELECT @CurrentLatestBackup = MAX(backup_finish_date)
    FROM msdb.dbo.backupset
    WHERE [type] IN('D','I')
    AND is_copy_only = 0
    AND is_snapshot = 0
    AND is_damaged = 0
    AND database_name = @CurrentDatabase

    -- Set database message
    SET @DatabaseMessage = 'DateTime: ' + CONVERT(nvarchar,GETDATE(),120) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Database: ' + QUOTENAME(@CurrentDatabase) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Status: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Status') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Mirroring role: ' + ISNULL(@CurrentMirroringRole,'None') + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Standby: ' + CASE WHEN DATABASEPROPERTYEX(@CurrentDatabase,'IsInStandBy') = 1 THEN 'Yes' ELSE 'No' END + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Updateability: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Updateability') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'User access: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'UserAccess') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Is accessible: ' + CASE WHEN @CurrentIsDatabaseAccessible = 1 THEN 'Yes' ELSE 'No' END + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Recovery model: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Recovery') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Differential base LSN: ' + ISNULL(CAST(@CurrentDifferentialLSN AS nvarchar),'NULL') + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Last log backup LSN: ' + ISNULL(CAST(@CurrentLogLSN AS nvarchar),'NULL') + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = REPLACE(@DatabaseMessage,'%','%%')
    RAISERROR(@DatabaseMessage,10,1) WITH NOWAIT

    IF DATABASEPROPERTYEX(@CurrentDatabase,'Status') = 'ONLINE'
    AND NOT (DATABASEPROPERTYEX(@CurrentDatabase,'UserAccess') = 'SINGLE_USER' AND @CurrentIsDatabaseAccessible = 0)
    AND DATABASEPROPERTYEX(@CurrentDatabase,'IsInStandBy') = 0
    AND NOT (@CurrentBackupType = 'LOG' AND (DATABASEPROPERTYEX(@CurrentDatabase,'Recovery') = 'SIMPLE' OR @CurrentLogLSN IS NULL))
    AND NOT (@CurrentBackupType = 'DIFF' AND @CurrentDifferentialLSN IS NULL)
    AND NOT (@CurrentBackupType IN('DIFF','LOG') AND @CurrentDatabase = 'master')
    BEGIN

      -- Set variables
      SET @CurrentDate = GETDATE()

      IF @CleanupTime IS NULL OR (@CurrentBackupType = 'LOG' AND @CurrentLatestBackup IS NULL)
      BEGIN
        SET @CurrentCleanupDate = NULL
      END
      ELSE
      IF @CurrentBackupType = 'LOG'
      BEGIN
        SET @CurrentCleanupDate = (SELECT MIN([Date]) FROM(SELECT DATEADD(hh,-(@CleanupTime),@CurrentDate) AS [Date] UNION SELECT @CurrentLatestBackup AS [Date]) Dates)
      END
      ELSE
      BEGIN
        SET @CurrentCleanupDate = DATEADD(hh,-(@CleanupTime),@CurrentDate)
      END

      SET @CurrentDatabaseFS = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(@CurrentDatabase,'\',''),'/',''),':',''),'*',''),'?',''),'"',''),'<',''),'>',''),'|',''),' ','')

      SELECT @CurrentFileExtension = CASE
      WHEN @BackupSoftware IS NULL AND @CurrentBackupType = 'FULL' THEN 'bak'
      WHEN @BackupSoftware IS NULL AND @CurrentBackupType = 'DIFF' THEN 'bak'
      WHEN @BackupSoftware IS NULL AND @CurrentBackupType = 'LOG' THEN 'trn'
      WHEN @BackupSoftware = 'LITESPEED' AND @CurrentBackupType = 'FULL' THEN 'bak'
      WHEN @BackupSoftware = 'LITESPEED' AND @CurrentBackupType = 'DIFF' THEN 'bak'
      WHEN @BackupSoftware = 'LITESPEED' AND @CurrentBackupType = 'LOG' THEN 'trn'
      WHEN @BackupSoftware = 'SQLBACKUP' AND @CurrentBackupType = 'FULL' THEN 'sqb'
      WHEN @BackupSoftware = 'SQLBACKUP' AND @CurrentBackupType = 'DIFF' THEN 'sqb'
      WHEN @BackupSoftware = 'SQLBACKUP' AND @CurrentBackupType = 'LOG' THEN 'sqb'
      WHEN @BackupSoftware = 'HYPERBAC' AND @CurrentBackupType = 'FULL' THEN 'hbc'
      WHEN @BackupSoftware = 'HYPERBAC' AND @CurrentBackupType = 'DIFF' THEN 'hbc'
      WHEN @BackupSoftware = 'HYPERBAC' AND @CurrentBackupType = 'LOG' THEN 'hbc'
      WHEN @BackupSoftware = 'SQLSAFE' AND @CurrentBackupType = 'FULL' THEN 'safe'
      WHEN @BackupSoftware = 'SQLSAFE' AND @CurrentBackupType = 'DIFF' THEN 'safe'
      WHEN @BackupSoftware = 'SQLSAFE' AND @CurrentBackupType = 'LOG' THEN 'safe'
      END

--//  SET @CurrentDirectory = @Directory + CASE WHEN RIGHT(@Directory,1) = '\' THEN '' ELSE '\' END + REPLACE(CAST(SERVERPROPERTY('servername') AS nvarchar),'\','$') + '\' + @CurrentDatabaseFS + '\' + UPPER(@CurrentBackupType)
--//  VersionOne V1 Paul S. Changed 4/13/11  
      SET @CurrentDirectory = @Directory 

      SET @CurrentFileNumber = 0

      WHILE @CurrentFileNumber < @NumberOfFiles
      BEGIN
        SET @CurrentFileNumber = @CurrentFileNumber + 1

--//    SET @CurrentFilePath = @CurrentDirectory + '\' + REPLACE(CAST(SERVERPROPERTY('servername') AS nvarchar),'\','$') + '_' + @CurrentDatabaseFS + '_' + UPPER(@CurrentBackupType) + '_' + REPLACE(REPLACE(REPLACE((CONVERT(nvarchar,@CurrentDate,120)),'-',''),' ','_'),':','') + CASE WHEN @NumberOfFiles > 1 AND @NumberOfFiles <= 9 THEN '_' + CAST(@CurrentFileNumber AS nvarchar) WHEN @NumberOfFiles >= 10 THEN '_' + RIGHT('0' + CAST(@CurrentFileNumber AS nvarchar),2) ELSE '' END + '.' + @CurrentFileExtension
--//    VersionOne V1 Paul S. Changed 4/13/11 

		SET @CurrentFilePath = @CurrentDirectory + '\' + @CurrentDatabaseFS + '_' + REPLACE(REPLACE(REPLACE((CONVERT(nvarchar,@CurrentDate,120)),'-','_'),' ','_'),':','') + CASE WHEN @NumberOfFiles > 1 AND @NumberOfFiles <= 9 THEN '_' + CAST(@CurrentFileNumber AS nvarchar) WHEN @NumberOfFiles >= 10 THEN '_' + RIGHT('0' + CAST(@CurrentFileNumber AS nvarchar),2) ELSE '' END + '.' + @CurrentFileExtension

        IF LEN(@CurrentFilePath) > 259
        BEGIN
          SET @CurrentFilePath = @CurrentDirectory + '\' + REPLACE(CAST(SERVERPROPERTY('servername') AS nvarchar),'\','$') + '_' + LEFT(@CurrentDatabaseFS,CASE WHEN (LEN(@CurrentDatabaseFS) + 259 - LEN(@CurrentFilePath) - 3) < 20 THEN 20 ELSE (LEN(@CurrentDatabaseFS) + 259 - LEN(@CurrentFilePath) - 3) END) + '...' + '_' + UPPER(@CurrentBackupType) + '_' + REPLACE(REPLACE(REPLACE((CONVERT(nvarchar,@CurrentDate,120)),'-',''),' ','_'),':','') + CASE WHEN @NumberOfFiles > 1 AND @NumberOfFiles <= 9 THEN '_' + CAST(@CurrentFileNumber AS nvarchar) WHEN @NumberOfFiles >= 10 THEN '_' + RIGHT('0' + CAST(@CurrentFileNumber AS nvarchar),2) ELSE '' END + '.' + @CurrentFileExtension
        END

        INSERT INTO @CurrentFiles (CurrentFilePath)
        SELECT @CurrentFilePath
      END

      -- Create directory
      SET @CurrentCommand01 = 'DECLARE @ReturnCode int EXECUTE @ReturnCode = master.dbo.xp_create_subdir N''' + REPLACE(@CurrentDirectory,'''','''''') + ''' IF @ReturnCode <> 0 RAISERROR(''Error creating directory.'', 16, 1)'
      EXECUTE @CurrentCommandOutput01 = [dbo].[CommandExecute] @CurrentCommand01, '', 1, @Execute
      SET @Error = @@ERROR
      IF @Error <> 0 SET @CurrentCommandOutput01 = @Error

      -- Perform a backup
      IF @CurrentCommandOutput01 = 0
      BEGIN
        IF @BackupSoftware IS NULL
        BEGIN
          SELECT @CurrentCommand02 = CASE
          WHEN @CurrentBackupType IN('DIFF','FULL') THEN 'BACKUP DATABASE ' + QUOTENAME(@CurrentDatabase) + ' TO'
          WHEN @CurrentBackupType = 'LOG' THEN 'BACKUP LOG ' + QUOTENAME(@CurrentDatabase) + ' TO'
          END

          SELECT @CurrentCommand02 = @CurrentCommand02 + ' DISK = N''' + REPLACE(CurrentFilePath,'''','''''') + '''' + CASE WHEN ROW_NUMBER() OVER (ORDER BY CurrentFilePath ASC) <> @NumberOfFiles THEN ',' ELSE '' END
          FROM @CurrentFiles
          ORDER BY CurrentFilePath ASC

          SET @CurrentCommand02 = @CurrentCommand02 + ' WITH '
          IF @CheckSum = 'Y' SET @CurrentCommand02 = @CurrentCommand02 + 'CHECKSUM'
          IF @CheckSum = 'N' SET @CurrentCommand02 = @CurrentCommand02 + 'NO_CHECKSUM'
          IF @Compress = 'Y' SET @CurrentCommand02 = @CurrentCommand02 + ', COMPRESSION'
          IF @Compress = 'N' AND @Version >= 10 SET @CurrentCommand02 = @CurrentCommand02 + ', NO_COMPRESSION'
          IF @CurrentBackupType = 'DIFF' SET @CurrentCommand02 = @CurrentCommand02 + ', DIFFERENTIAL'
          IF @CopyOnly = 'Y' SET @CurrentCommand02 = @CurrentCommand02 + ', COPY_ONLY'
          IF @BlockSize IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', BLOCKSIZE = ' + CAST(@BlockSize AS nvarchar)
          IF @BufferCount IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', BUFFERCOUNT = ' + CAST(@BufferCount AS nvarchar)
          IF @MaxTransferSize IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', MAXTRANSFERSIZE = ' + CAST(@MaxTransferSize AS nvarchar)
          IF @Description IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', DESCRIPTION = N''' + REPLACE(@Description,'''','''''') + ''''
        END

        IF @BackupSoftware = 'LITESPEED'
        BEGIN
          SELECT @CurrentCommand02 = CASE
          WHEN @CurrentBackupType IN('DIFF','FULL') THEN 'DECLARE @ReturnCode int EXECUTE @ReturnCode = master.dbo.xp_backup_database @database = N''' + REPLACE(@CurrentDatabase,'''','''''') + ''''
          WHEN @CurrentBackupType = 'LOG' THEN 'DECLARE @ReturnCode int EXECUTE @ReturnCode = master.dbo.xp_backup_log @database = N''' + REPLACE(@CurrentDatabase,'''','''''') + ''''
          END

          SELECT @CurrentCommand02 = @CurrentCommand02 + ', @filename = N''' + REPLACE(CurrentFilePath,'''','''''') + ''''
          FROM @CurrentFiles
          ORDER BY CurrentFilePath ASC

          SET @CurrentCommand02 = @CurrentCommand02 + ', @with = '''
          IF @CheckSum = 'Y' SET @CurrentCommand02 = @CurrentCommand02 + 'CHECKSUM'
          IF @CheckSum = 'N' SET @CurrentCommand02 = @CurrentCommand02 + 'NO_CHECKSUM'
          IF @CurrentBackupType = 'DIFF' SET @CurrentCommand02 = @CurrentCommand02 + ', DIFFERENTIAL'
          IF @CopyOnly = 'Y' SET @CurrentCommand02 = @CurrentCommand02 + ', COPY_ONLY'
          IF @BlockSize IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', BLOCKSIZE = ' + CAST(@BlockSize AS nvarchar)
          IF @BufferCount IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', BUFFERCOUNT = ' + CAST(@BufferCount AS nvarchar)
          IF @MaxTransferSize IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', MAXTRANSFERSIZE = ' + CAST(@MaxTransferSize AS nvarchar)
          SET @CurrentCommand02 = @CurrentCommand02 + ''''
          IF @CompressionLevel IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', @compressionlevel = ' + CAST(@CompressionLevel AS nvarchar)
          IF @Threads IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', @threads = ' + CAST(@Threads AS nvarchar)
          IF @Throttle IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', @throttle = ' + CAST(@Throttle AS nvarchar)
          IF @Description IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', @desc = N''' + REPLACE(@Description,'''','''''') + ''''
          SET @CurrentCommand02 = @CurrentCommand02 + ' IF @ReturnCode <> 0 RAISERROR(''Error performing LiteSpeed backup.'', 16, 1)'
        END

        IF @BackupSoftware = 'SQLBACKUP'
        BEGIN
          SELECT @CurrentCommand02 = CASE
          WHEN @CurrentBackupType IN('DIFF','FULL') THEN 'BACKUP DATABASE ' + QUOTENAME(@CurrentDatabase) + ' TO'
          WHEN @CurrentBackupType = 'LOG' THEN 'BACKUP LOG ' + QUOTENAME(@CurrentDatabase) + ' TO'
          END

          SELECT @CurrentCommand02 = @CurrentCommand02 + ' DISK = N''' + REPLACE(CurrentFilePath,'''','''''') + '''' + CASE WHEN ROW_NUMBER() OVER (ORDER BY CurrentFilePath ASC) <> @NumberOfFiles THEN ',' ELSE '' END
          FROM @CurrentFiles
          ORDER BY CurrentFilePath ASC

          SET @CurrentCommand02 = @CurrentCommand02 + ' WITH '
          IF @CheckSum = 'Y' SET @CurrentCommand02 = @CurrentCommand02 + 'CHECKSUM'
          IF @CheckSum = 'N' SET @CurrentCommand02 = @CurrentCommand02 + 'NO_CHECKSUM'
          IF @CurrentBackupType = 'DIFF' SET @CurrentCommand02 = @CurrentCommand02 + ', DIFFERENTIAL'
          IF @CopyOnly = 'Y' SET @CurrentCommand02 = @CurrentCommand02 + ', COPY_ONLY'
          IF @CompressionLevel IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', COMPRESSION = ' + CAST(@CompressionLevel AS nvarchar)
          IF @Threads IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', THREADCOUNT = ' + CAST(@Threads AS nvarchar)
          IF @Description IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', DESCRIPTION = N''' + REPLACE(@Description,'''','''''') + ''''
          SET @CurrentCommand02 = 'DECLARE @ReturnCode int EXECUTE @ReturnCode = master..sqlbackup N''-SQL "' + REPLACE(@CurrentCommand02,'''','''''') + '"''' + ' IF @ReturnCode <> 0 RAISERROR(''Error performing SQLBackup backup.'', 16, 1)'
        END

        IF @BackupSoftware = 'HYPERBAC'
        BEGIN
          SELECT @CurrentCommand02 = CASE
          WHEN @CurrentBackupType IN('DIFF','FULL') THEN 'BACKUP DATABASE ' + QUOTENAME(@CurrentDatabase) + ' TO'
          WHEN @CurrentBackupType = 'LOG' THEN 'BACKUP LOG ' + QUOTENAME(@CurrentDatabase) + ' TO'
          END

          SELECT @CurrentCommand02 = @CurrentCommand02 + ' DISK = N''' + REPLACE(CurrentFilePath,'''','''''') + '''' + CASE WHEN ROW_NUMBER() OVER (ORDER BY CurrentFilePath ASC) <> @NumberOfFiles THEN ',' ELSE '' END
          FROM @CurrentFiles
          ORDER BY CurrentFilePath ASC

          SET @CurrentCommand02 = @CurrentCommand02 + ' WITH '
          IF @CheckSum = 'Y' SET @CurrentCommand02 = @CurrentCommand02 + 'CHECKSUM'
          IF @CheckSum = 'N' SET @CurrentCommand02 = @CurrentCommand02 + 'NO_CHECKSUM'
          IF @CurrentBackupType = 'DIFF' SET @CurrentCommand02 = @CurrentCommand02 + ', DIFFERENTIAL'
          IF @CopyOnly = 'Y' SET @CurrentCommand02 = @CurrentCommand02 + ', COPY_ONLY'
          IF @BlockSize IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', BLOCKSIZE = ' + CAST(@BlockSize AS nvarchar)
          IF @BufferCount IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', BUFFERCOUNT = ' + CAST(@BufferCount AS nvarchar)
          IF @MaxTransferSize IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', MAXTRANSFERSIZE = ' + CAST(@MaxTransferSize AS nvarchar)
          IF @Description IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', DESCRIPTION = N''' + REPLACE(@Description,'''','''''') + ''''
        END

        IF @BackupSoftware = 'SQLSAFE'
        BEGIN
          SET @CurrentCommand02 = 'DECLARE @ReturnCode int EXECUTE @ReturnCode = master.dbo.xp_ss_backup @database = N''' + REPLACE(@CurrentDatabase,'''','''''') + ''''

          SELECT @CurrentCommand02 = @CurrentCommand02 + ', ' + CASE WHEN ROW_NUMBER() OVER (ORDER BY CurrentFilePath ASC) = 1 THEN '@filename' ELSE '@backupfile' END + ' = N''' + REPLACE(CurrentFilePath,'''','''''') + ''''
          FROM @CurrentFiles
          ORDER BY CurrentFilePath ASC

          SET @CurrentCommand02 = @CurrentCommand02 + ', @backuptype = ' + CASE WHEN @CurrentBackupType = 'FULL' THEN '''Full''' WHEN @CurrentBackupType = 'DIFF' THEN '''Differential''' WHEN @CurrentBackupType = 'LOG' THEN '''Log''' END
          SET @CurrentCommand02 = @CurrentCommand02 + ', @checksum = ' + CASE WHEN @CheckSum = 'Y' THEN '1' WHEN @CheckSum = 'N' THEN '0' END
          SET @CurrentCommand02 = @CurrentCommand02 + ', @copyonly = ' + CASE WHEN @CopyOnly = 'Y' THEN '1' WHEN @CopyOnly = 'N' THEN '0' END
          IF @CompressionLevel IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', @compressionlevel = ' + CAST(@CompressionLevel AS nvarchar)
          IF @Threads IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', @threads = ' + CAST(@Threads AS nvarchar)
          IF @Description IS NOT NULL SET @CurrentCommand02 = @CurrentCommand02 + ', @desc = N''' + REPLACE(@Description,'''','''''') + ''''
          SET @CurrentCommand02 = @CurrentCommand02 + ' IF @ReturnCode <> 0 RAISERROR(''Error performing SQLsafe backup.'', 16, 1)'
        END

        EXECUTE @CurrentCommandOutput02 = [dbo].[CommandExecute] @CurrentCommand02, '', 1, @Execute
        SET @Error = @@ERROR
        IF @Error <> 0 SET @CurrentCommandOutput02 = @Error
      END

      -- Verify the backup
      IF @CurrentCommandOutput02 = 0 AND @Verify = 'Y'
      BEGIN
        IF @BackupSoftware IS NULL
        BEGIN
          SET @CurrentCommand03 = 'RESTORE VERIFYONLY FROM'

          SELECT @CurrentCommand03 = @CurrentCommand03 + ' DISK = N''' + REPLACE(CurrentFilePath,'''','''''') + '''' + CASE WHEN ROW_NUMBER() OVER (ORDER BY CurrentFilePath ASC) <> @NumberOfFiles THEN ',' ELSE '' END
          FROM @CurrentFiles
          ORDER BY CurrentFilePath ASC
        END

        IF @BackupSoftware = 'LITESPEED'
        BEGIN
          SET @CurrentCommand03 = 'DECLARE @ReturnCode int EXECUTE @ReturnCode = master.dbo.xp_restore_verifyonly'

          SELECT @CurrentCommand03 = @CurrentCommand03 + ' @filename = N''' + REPLACE(CurrentFilePath,'''','''''') + '''' + CASE WHEN ROW_NUMBER() OVER (ORDER BY CurrentFilePath ASC) <> @NumberOfFiles THEN ',' ELSE '' END
          FROM @CurrentFiles
          ORDER BY CurrentFilePath ASC

          SET @CurrentCommand03 = @CurrentCommand03 + ' IF @ReturnCode <> 0 RAISERROR(''Error verifying LiteSpeed backup.'', 16, 1)'
        END

        IF @BackupSoftware = 'SQLBACKUP'
        BEGIN
          SET @CurrentCommand03 = 'RESTORE VERIFYONLY FROM'

          SELECT @CurrentCommand03 = @CurrentCommand03 + ' DISK = N''' + REPLACE(CurrentFilePath,'''','''''') + '''' + CASE WHEN ROW_NUMBER() OVER (ORDER BY CurrentFilePath ASC) <> @NumberOfFiles THEN ',' ELSE '' END
          FROM @CurrentFiles
          ORDER BY CurrentFilePath ASC

          SET @CurrentCommand03 = 'DECLARE @ReturnCode int EXECUTE @ReturnCode = master..sqlbackup N''-SQL "' + REPLACE(@CurrentCommand03,'''','''''') + '"''' + ' IF @ReturnCode <> 0 RAISERROR(''Error verifying SQLBackup backup.'', 16, 1)'
        END

        IF @BackupSoftware = 'HYPERBAC'
        BEGIN
          SET @CurrentCommand03 = 'RESTORE VERIFYONLY FROM'

          SELECT @CurrentCommand03 = @CurrentCommand03 + ' DISK = N''' + REPLACE(CurrentFilePath,'''','''''') + '''' + CASE WHEN ROW_NUMBER() OVER (ORDER BY CurrentFilePath ASC) <> @NumberOfFiles THEN ',' ELSE '' END
          FROM @CurrentFiles
          ORDER BY CurrentFilePath ASC
        END

        IF @BackupSoftware = 'SQLSAFE'
        BEGIN
          SET @CurrentCommand03 = 'DECLARE @ReturnCode int EXECUTE @ReturnCode = master.dbo.xp_ss_verify @database = N''' + REPLACE(@CurrentDatabase,'''','''''') + ''''

          SELECT @CurrentCommand03 = @CurrentCommand03 + ', ' + CASE WHEN ROW_NUMBER() OVER (ORDER BY CurrentFilePath ASC) = 1 THEN '@filename' ELSE '@backupfile' END + ' = N''' + REPLACE(CurrentFilePath,'''','''''') + ''''
          FROM @CurrentFiles
          ORDER BY CurrentFilePath ASC
          SET @CurrentCommand03 = @CurrentCommand03 + ' IF @ReturnCode <> 0 RAISERROR(''Error verifying SQLsafe backup.'', 16, 1)'
        END

        EXECUTE @CurrentCommandOutput03 = [dbo].[CommandExecute] @CurrentCommand03, '', 1, @Execute
        SET @Error = @@ERROR
        IF @Error <> 0 SET @CurrentCommandOutput03 = @Error
      END

      -- Delete old backup files
      IF (@CurrentCommandOutput02 = 0 AND @Verify = 'N' AND @CurrentCleanupDate IS NOT NULL)
      OR (@CurrentCommandOutput02 = 0 AND @Verify = 'Y' AND @CurrentCommandOutput03 = 0 AND @CurrentCleanupDate IS NOT NULL)
      BEGIN
        IF @BackupSoftware IS NULL
        BEGIN
          SET @CurrentCommand04 = 'DECLARE @ReturnCode int EXECUTE @ReturnCode = master.dbo.xp_delete_file 0, N''' + REPLACE(@CurrentDirectory,'''','''''') + ''', ''' + @CurrentFileExtension + ''', ''' + CONVERT(nvarchar(19),@CurrentCleanupDate,126) + ''' IF @ReturnCode <> 0 RAISERROR(''Error deleting files.'', 16, 1)'
        END

        IF @BackupSoftware = 'LITESPEED'
        BEGIN
          SET @CurrentCommand04 = 'DECLARE @ReturnCode int EXECUTE @ReturnCode = master.dbo.xp_slssqlmaint N''-MAINTDEL -DELFOLDER "' + REPLACE(@CurrentDirectory,'''','''''') + '" -DELEXTENSION "' + @CurrentFileExtension + '" -DELUNIT "' + CAST(DATEDIFF(mi,@CurrentCleanupDate,GETDATE()) + 1 AS nvarchar) + '" -DELUNITTYPE "minutes" -DELUSEAGE'' IF @ReturnCode <> 0 RAISERROR(''Error deleting LiteSpeed backup files.'', 16, 1)'
        END

        IF @BackupSoftware = 'SQLBACKUP'
        BEGIN
          SET @CurrentCommand04 = 'DECLARE @ReturnCode int EXECUTE @ReturnCode = master.dbo.sqbutility 1032, N''' + REPLACE(@CurrentDatabase,'''','''''') + ''', N''' + REPLACE(@CurrentDirectory,'''','''''') + ''', ''' + CASE WHEN @CurrentBackupType = 'FULL' THEN 'D' WHEN @CurrentBackupType = 'DIFF' THEN 'I' WHEN @CurrentBackupType = 'LOG' THEN 'L' END + ''', ''' + CAST(DATEDIFF(hh,@CurrentCleanupDate,GETDATE()) + 1 AS nvarchar) + 'h'' IF @ReturnCode <> 0 RAISERROR(''Error deleting SQLBackup backup files.'', 16, 1)'
        END

        IF @BackupSoftware = 'HYPERBAC'
        BEGIN
          SET @CurrentCommand04 = 'DECLARE @ReturnCode int EXECUTE @ReturnCode = master.dbo.xp_delete_file 0, N''' + REPLACE(@CurrentDirectory,'''','''''') + ''', ''' + @CurrentFileExtension + ''', ''' + CONVERT(nvarchar(19),@CurrentCleanupDate,126) + ''' IF @ReturnCode <> 0 RAISERROR(''Error deleting files.'', 16, 1)'
        END

        IF @BackupSoftware = 'SQLSAFE'
        BEGIN
          SET @CurrentCommand04 = 'DECLARE @ReturnCode int EXECUTE @ReturnCode = master.dbo.xp_ss_delete @filename = N''' + REPLACE(@CurrentDirectory,'''','''''') + '\*.' + @CurrentFileExtension + ''', @age = ''' + CAST(DATEDIFF(mi,@CurrentCleanupDate,GETDATE()) + 1 AS nvarchar) + 'Minutes'' IF @ReturnCode <> 0 RAISERROR(''Error deleting SQLsafe backup files.'', 16, 1)'
        END

        EXECUTE @CurrentCommandOutput04 = [dbo].[CommandExecute] @CurrentCommand04, '', 1, @Execute
        SET @Error = @@ERROR
        IF @Error <> 0 SET @CurrentCommandOutput04 = @Error
      END

    END

    -- Update that the database is completed
    UPDATE @tmpDatabases
    SET Completed = 1
    WHERE ID = @CurrentID

    -- Clear variables
    SET @CurrentID = NULL
    SET @CurrentDatabase = NULL
    SET @CurrentBackupType = NULL
    SET @CurrentFileExtension = NULL
    SET @CurrentFileNumber = NULL
    SET @CurrentDifferentialLSN = NULL
    SET @CurrentLogLSN = NULL
    SET @CurrentLatestBackup = NULL
    SET @CurrentDatabaseFS = NULL
    SET @CurrentDirectory = NULL
    SET @CurrentFilePath = NULL
    SET @CurrentDate = NULL
    SET @CurrentCleanupDate = NULL
    SET @CurrentIsDatabaseAccessible = NULL
    SET @CurrentMirroringRole = NULL

    SET @CurrentCommand01 = NULL
    SET @CurrentCommand02 = NULL
    SET @CurrentCommand03 = NULL
    SET @CurrentCommand04 = NULL

    SET @CurrentCommandOutput01 = NULL
    SET @CurrentCommandOutput02 = NULL
    SET @CurrentCommandOutput03 = NULL
    SET @CurrentCommandOutput04 = NULL

    DELETE FROM @CurrentFiles

  END

  ----------------------------------------------------------------------------------------------------
  --// Log completing information                                                                 //--
  ----------------------------------------------------------------------------------------------------

  Logging:
  SET @EndMessage = 'DateTime: ' + CONVERT(nvarchar,GETDATE(),120)
  SET @EndMessage = REPLACE(@EndMessage,'%','%%')
  RAISERROR(@EndMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------

END
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[DatabaseIntegrityCheck]

@Databases nvarchar(max),
@PhysicalOnly nvarchar(max) = 'N',
@NoIndex nvarchar(max) = 'N',
@ExtendedLogicalChecks nvarchar(max) = 'N',
@TabLock nvarchar(max) = 'N',
@Execute nvarchar(max) = 'Y'

AS

BEGIN

  ----------------------------------------------------------------------------------------------------
  --// Set options                                                                                //--
  ----------------------------------------------------------------------------------------------------

  SET NOCOUNT ON

  ----------------------------------------------------------------------------------------------------
  --// Declare variables                                                                          //--
  ----------------------------------------------------------------------------------------------------

  DECLARE @StartMessage nvarchar(max)
  DECLARE @EndMessage nvarchar(max)
  DECLARE @DatabaseMessage nvarchar(max)
  DECLARE @ErrorMessage nvarchar(max)

  DECLARE @Version numeric(18,10)

  DECLARE @CurrentID int
  DECLARE @CurrentDatabase nvarchar(max)
  DECLARE @CurrentIsDatabaseAccessible bit
  DECLARE @CurrentMirroringRole nvarchar(max)

  DECLARE @CurrentCommand01 nvarchar(max)

  DECLARE @CurrentCommandOutput01 int

  DECLARE @tmpDatabases TABLE (ID int IDENTITY PRIMARY KEY,
                               DatabaseName nvarchar(max),
                               Completed bit)

  DECLARE @Error int

  SET @Error = 0

  SET @Version = CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)),CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - 1) + '.' + REPLACE(RIGHT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)), LEN(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)))),'.','') AS numeric(18,10))

  ----------------------------------------------------------------------------------------------------
  --// Log initial information                                                                    //--
  ----------------------------------------------------------------------------------------------------

  SET @StartMessage = 'DateTime: ' + CONVERT(nvarchar,GETDATE(),120) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Server: ' + CAST(SERVERPROPERTY('ServerName') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Version: ' + CAST(SERVERPROPERTY('ProductVersion') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Edition: ' + CAST(SERVERPROPERTY('Edition') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Procedure: ' + QUOTENAME(DB_NAME(DB_ID())) + '.' + (SELECT QUOTENAME(sys.schemas.name) FROM sys.schemas INNER JOIN sys.objects ON sys.schemas.[schema_id] = sys.objects.[schema_id] WHERE [object_id] = @@PROCID) + '.' + QUOTENAME(OBJECT_NAME(@@PROCID)) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Parameters: @Databases = ' + ISNULL('''' + REPLACE(@Databases,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @PhysicalOnly = ' + ISNULL('''' + REPLACE(@PhysicalOnly,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @NoIndex = ' + ISNULL('''' + REPLACE(@NoIndex,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @ExtendedLogicalChecks = ' + ISNULL('''' + REPLACE(@ExtendedLogicalChecks,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @TabLock = ' + ISNULL('''' + REPLACE(@TabLock,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @Execute = ' + ISNULL('''' + REPLACE(@Execute,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + CHAR(13) + CHAR(10)
  SET @StartMessage = REPLACE(@StartMessage,'%','%%')
  RAISERROR(@StartMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------
  --// Select databases                                                                           //--
  ----------------------------------------------------------------------------------------------------

  IF @Databases IS NULL OR @Databases = ''
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Databases is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  INSERT INTO @tmpDatabases (DatabaseName, Completed)
  SELECT DatabaseName AS DatabaseName,
         0 AS Completed
  FROM dbo.DatabaseSelect (@Databases)
  ORDER BY DatabaseName ASC

  IF @@ERROR <> 0 OR (@@ROWCOUNT = 0 AND @Databases <> 'USER_DATABASES')
  BEGIN
    SET @ErrorMessage = 'Error selecting databases.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Check input parameters                                                                     //--
  ----------------------------------------------------------------------------------------------------

  IF @PhysicalOnly NOT IN ('Y','N') OR @PhysicalOnly IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @PhysicalOnly is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @NoIndex NOT IN ('Y','N') OR @NoIndex IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @NoIndex is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @ExtendedLogicalChecks NOT IN ('Y','N') OR @ExtendedLogicalChecks IS NULL OR (@ExtendedLogicalChecks = 'Y' AND NOT @Version >= 10)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @ExtendedLogicalChecks is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @PhysicalOnly = 'Y' AND @ExtendedLogicalChecks = 'Y'
  BEGIN
    SET @ErrorMessage = 'Extended Logical Checks and Physical Only cannot be used together.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF (@ExtendedLogicalChecks = 'Y' AND NOT (@Version >= 10))
  BEGIN
    SET @ErrorMessage = 'Extended Logical Checks are only supported in SQL Server 2008 and SQL Server 2008 R2.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @TabLock NOT IN ('Y','N') OR @TabLock IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @TabLock is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Execute NOT IN('Y','N') OR @Execute IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Execute is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Check error variable                                                                       //--
  ----------------------------------------------------------------------------------------------------

  IF @Error <> 0 GOTO Logging

  ----------------------------------------------------------------------------------------------------
  --// Execute commands                                                                           //--
  ----------------------------------------------------------------------------------------------------

  WHILE EXISTS (SELECT * FROM @tmpDatabases WHERE Completed = 0)
  BEGIN

    SELECT TOP 1 @CurrentID = ID,
                 @CurrentDatabase = DatabaseName
    FROM @tmpDatabases
    WHERE Completed = 0
    ORDER BY ID ASC

    IF EXISTS (SELECT * FROM sys.database_recovery_status WHERE database_id = DB_ID(@CurrentDatabase) AND database_guid IS NOT NULL)
    BEGIN
      SET @CurrentIsDatabaseAccessible = 1
    END
    ELSE
    BEGIN
      SET @CurrentIsDatabaseAccessible = 0
    END

    SELECT @CurrentMirroringRole = mirroring_role_desc
    FROM sys.database_mirroring
    WHERE database_id = DB_ID(@CurrentDatabase)

    -- Set database message
    SET @DatabaseMessage = 'DateTime: ' + CONVERT(nvarchar,GETDATE(),120) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Database: ' + QUOTENAME(@CurrentDatabase) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Status: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Status') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Mirroring role: ' + ISNULL(@CurrentMirroringRole,'None') + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Standby: ' + CASE WHEN DATABASEPROPERTYEX(@CurrentDatabase,'IsInStandBy') = 1 THEN 'Yes' ELSE 'No' END + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Updateability: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Updateability') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'User access: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'UserAccess') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Is accessible: ' + CASE WHEN @CurrentIsDatabaseAccessible = 1 THEN 'Yes' ELSE 'No' END + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Recovery model: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Recovery') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = REPLACE(@DatabaseMessage,'%','%%')
    RAISERROR(@DatabaseMessage,10,1) WITH NOWAIT

    IF DATABASEPROPERTYEX(@CurrentDatabase,'Status') = 'ONLINE'
    AND NOT (DATABASEPROPERTYEX(@CurrentDatabase,'UserAccess') = 'SINGLE_USER' AND @CurrentIsDatabaseAccessible = 0)
    BEGIN
      SET @CurrentCommand01 = 'DBCC CHECKDB (' + QUOTENAME(@CurrentDatabase)
      IF @NoIndex = 'Y' SET @CurrentCommand01 = @CurrentCommand01 + ', NOINDEX'
      SET @CurrentCommand01 = @CurrentCommand01 + ') WITH NO_INFOMSGS, ALL_ERRORMSGS'
      IF @PhysicalOnly = 'N' SET @CurrentCommand01 = @CurrentCommand01 + ', DATA_PURITY'
      IF @PhysicalOnly = 'Y' SET @CurrentCommand01 = @CurrentCommand01 + ', PHYSICAL_ONLY'
      IF @ExtendedLogicalChecks = 'Y' SET @CurrentCommand01 = @CurrentCommand01 + ', EXTENDED_LOGICAL_CHECKS'
      IF @TabLock = 'Y' SET @CurrentCommand01 = @CurrentCommand01 + ', TABLOCK'

      EXECUTE @CurrentCommandOutput01 = [dbo].[CommandExecute] @CurrentCommand01, '', 1, @Execute
      SET @Error = @@ERROR
      IF @Error <> 0 SET @CurrentCommandOutput01 = @Error
    END

    -- Update that the database is completed
    UPDATE @tmpDatabases
    SET Completed = 1
    WHERE ID = @CurrentID

    -- Clear variables
    SET @CurrentID = NULL
    SET @CurrentDatabase = NULL
    SET @CurrentIsDatabaseAccessible = NULL
    SET @CurrentMirroringRole = NULL

    SET @CurrentCommand01 = NULL

    SET @CurrentCommandOutput01 = NULL

  END

  ----------------------------------------------------------------------------------------------------
  --// Log completing information                                                                 //--
  ----------------------------------------------------------------------------------------------------

  Logging:
  SET @EndMessage = 'DateTime: ' + CONVERT(nvarchar,GETDATE(),120)
  SET @EndMessage = REPLACE(@EndMessage,'%','%%')
  RAISERROR(@EndMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------

END
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[IndexOptimize]

@Databases nvarchar(max),
@FragmentationHigh nvarchar(max) = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
@FragmentationMedium nvarchar(max) = 'INDEX_REORGANIZE,INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
@FragmentationLow nvarchar(max) = NULL,
@FragmentationLevel1 int = 5,
@FragmentationLevel2 int = 30,
@PageCountLevel int = 1000,
@SortInTempdb nvarchar(max) = 'N',
@MaxDOP int = NULL,
@FillFactor int = NULL,
@PadIndex nvarchar(max) = NULL,
@LOBCompaction nvarchar(max) = 'Y',
@UpdateStatistics nvarchar(max) = NULL,
@OnlyModifiedStatistics nvarchar(max) = 'N',
@StatisticsSample int = NULL,
@StatisticsResample nvarchar(max) = 'N',
@PartitionLevel nvarchar(max) = 'N',
@TimeLimit int = NULL,
@Indexes nvarchar(max) = NULL,
@Delay int = NULL,
@Execute nvarchar(max) = 'Y'

AS

BEGIN

  ----------------------------------------------------------------------------------------------------
  --// Set options                                                                                //--
  ----------------------------------------------------------------------------------------------------

  SET NOCOUNT ON

  SET LOCK_TIMEOUT 3600000

  ----------------------------------------------------------------------------------------------------
  --// Declare variables                                                                          //--
  ----------------------------------------------------------------------------------------------------

  DECLARE @StartMessage nvarchar(max)
  DECLARE @EndMessage nvarchar(max)
  DECLARE @DatabaseMessage nvarchar(max)
  DECLARE @ErrorMessage nvarchar(max)

  DECLARE @Version numeric(18,10)

  DECLARE @StartTime datetime

  DECLARE @CurrentIndexList nvarchar(max)
  DECLARE @CurrentIndexItem nvarchar(max)
  DECLARE @CurrentIndexPosition int

  DECLARE @CurrentID int
  DECLARE @CurrentDatabase nvarchar(max)
  DECLARE @CurrentIsDatabaseAccessible bit
  DECLARE @CurrentMirroringRole nvarchar(max)

  DECLARE @CurrentCommandSelect01 nvarchar(max)
  DECLARE @CurrentCommandSelect02 nvarchar(max)
  DECLARE @CurrentCommandSelect03 nvarchar(max)
  DECLARE @CurrentCommandSelect04 nvarchar(max)
  DECLARE @CurrentCommandSelect05 nvarchar(max)
  DECLARE @CurrentCommandSelect06 nvarchar(max)
  DECLARE @CurrentCommandSelect07 nvarchar(max)
  DECLARE @CurrentCommandSelect08 nvarchar(max)

  DECLARE @CurrentCommand01 nvarchar(max)
  DECLARE @CurrentCommand02 nvarchar(max)

  DECLARE @CurrentCommandOutput01 int
  DECLARE @CurrentCommandOutput02 int

  DECLARE @CurrentIxID int
  DECLARE @CurrentSchemaID int
  DECLARE @CurrentSchemaName nvarchar(max)
  DECLARE @CurrentObjectID int
  DECLARE @CurrentObjectName nvarchar(max)
  DECLARE @CurrentObjectType nvarchar(max)
  DECLARE @CurrentIndexID int
  DECLARE @CurrentIndexName nvarchar(max)
  DECLARE @CurrentIndexType int
  DECLARE @CurrentStatisticsID int
  DECLARE @CurrentStatisticsName nvarchar(max)
  DECLARE @CurrentPartitionID bigint
  DECLARE @CurrentPartitionNumber int
  DECLARE @CurrentPartitionCount int
  DECLARE @CurrentIsPartition bit
  DECLARE @CurrentIndexExists bit
  DECLARE @CurrentStatisticsExists bit
  DECLARE @CurrentIsLOB bit
  DECLARE @CurrentAllowPageLocks bit
  DECLARE @CurrentNoRecompute bit
  DECLARE @CurrentStatisticsModified bit
  DECLARE @CurrentOnReadOnlyFileGroup bit
  DECLARE @CurrentFragmentationLevel float
  DECLARE @CurrentPageCount bigint
  DECLARE @CurrentFragmentationGroup nvarchar(max)
  DECLARE @CurrentAction nvarchar(max)
  DECLARE @CurrentMaxDOP int
  DECLARE @CurrentUpdateStatistics nvarchar(max)
  DECLARE @CurrentComment nvarchar(max)
  DECLARE @CurrentDelay datetime

  DECLARE @tmpDatabases TABLE (ID int IDENTITY PRIMARY KEY,
                               DatabaseName nvarchar(max),
                               Completed bit)

  DECLARE @tmpIndexesStatistics TABLE (IxID int IDENTITY PRIMARY KEY,
                                       SchemaID int,
                                       SchemaName nvarchar(max),
                                       ObjectID int,
                                       ObjectName nvarchar(max),
                                       ObjectType nvarchar(max),
                                       IndexID int,
                                       IndexName nvarchar(max),
                                       IndexType int,
                                       StatisticsID int,
                                       StatisticsName nvarchar(max),
                                       PartitionID bigint,
                                       PartitionNumber int,
                                       PartitionCount int,
                                       Selected bit,
                                       Completed bit)

  DECLARE @SelectedIndexes TABLE (DatabaseName nvarchar(max),
                                  SchemaName nvarchar(max),
                                  ObjectName nvarchar(max),
                                  IndexName nvarchar(max),
                                  Selected bit)

  DECLARE @tmpIndexExists TABLE ([Count] int)

  DECLARE @tmpStatisticsExists TABLE ([Count] int)

  DECLARE @tmpIsLOB TABLE ([Count] int)

  DECLARE @tmpAllowPageLocks TABLE ([Count] int)

  DECLARE @tmpNoRecompute TABLE ([Count] int)

  DECLARE @tmpStatisticsModified TABLE ([Count] int)

  DECLARE @tmpOnReadOnlyFileGroup TABLE ([Count] int)

  DECLARE @Actions TABLE ([Action] nvarchar(max))

  INSERT INTO @Actions([Action]) VALUES('INDEX_REBUILD_ONLINE')
  INSERT INTO @Actions([Action]) VALUES('INDEX_REBUILD_OFFLINE')
  INSERT INTO @Actions([Action]) VALUES('INDEX_REORGANIZE')

  DECLARE @ActionsPreferred TABLE (FragmentationGroup nvarchar(max),
                                   Priority int,
                                   [Action] nvarchar(max))

  DECLARE @CurrentActionsAllowed TABLE ([Action] nvarchar(max))

  DECLARE @Error int

  SET @Error = 0

  SET @Version = CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)),CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - 1) + '.' + REPLACE(RIGHT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)), LEN(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)))),'.','') AS numeric(18,10))

  SET @CurrentDelay = DATEADD(ss,@Delay,'1900-01-01')

  ----------------------------------------------------------------------------------------------------
  --// Log initial information                                                                    //--
  ----------------------------------------------------------------------------------------------------

  SET @StartTime = CONVERT(datetime,CONVERT(nvarchar,GETDATE(),120),120)

  SET @StartMessage = 'DateTime: ' + CONVERT(nvarchar,@StartTime,120) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Server: ' + CAST(SERVERPROPERTY('ServerName') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Version: ' + CAST(SERVERPROPERTY('ProductVersion') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Edition: ' + CAST(SERVERPROPERTY('Edition') AS nvarchar) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Procedure: ' + QUOTENAME(DB_NAME(DB_ID())) + '.' + (SELECT QUOTENAME(sys.schemas.name) FROM sys.schemas INNER JOIN sys.objects ON sys.schemas.[schema_id] = sys.objects.[schema_id] WHERE [object_id] = @@PROCID) + '.' + QUOTENAME(OBJECT_NAME(@@PROCID)) + CHAR(13) + CHAR(10)
  SET @StartMessage = @StartMessage + 'Parameters: @Databases = ' + ISNULL('''' + REPLACE(@Databases,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @FragmentationHigh = ' + ISNULL('''' + REPLACE(@FragmentationHigh,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @FragmentationMedium = ' + ISNULL('''' + REPLACE(@FragmentationMedium,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @FragmentationLow = ' + ISNULL('''' + REPLACE(@FragmentationLow,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @FragmentationLevel1 = ' + ISNULL(CAST(@FragmentationLevel1 AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @FragmentationLevel2 = ' + ISNULL(CAST(@FragmentationLevel2 AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @PageCountLevel = ' + ISNULL(CAST(@PageCountLevel AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @SortInTempdb = ' + ISNULL('''' + REPLACE(@SortInTempdb,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @MaxDOP = ' + ISNULL(CAST(@MaxDOP AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @FillFactor = ' + ISNULL(CAST(@FillFactor AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @PadIndex = ' + ISNULL('''' + REPLACE(@PadIndex,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @LOBCompaction = ' + ISNULL('''' + REPLACE(@LOBCompaction,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @UpdateStatistics = ' + ISNULL('''' + REPLACE(@UpdateStatistics,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @OnlyModifiedStatistics = ' + ISNULL('''' + REPLACE(@OnlyModifiedStatistics,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @StatisticsSample = ' + ISNULL(CAST(@StatisticsSample AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @StatisticsResample = ' + ISNULL('''' + REPLACE(@StatisticsResample,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @PartitionLevel = ' + ISNULL('''' + REPLACE(@PartitionLevel,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @TimeLimit = ' + ISNULL(CAST(@TimeLimit AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @Indexes = ' + ISNULL('''' + REPLACE(@Indexes,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + ', @Delay = ' + ISNULL(CAST(@Delay AS nvarchar),'NULL')
  SET @StartMessage = @StartMessage + ', @Execute = ' + ISNULL('''' + REPLACE(@Execute,'''','''''') + '''','NULL')
  SET @StartMessage = @StartMessage + CHAR(13) + CHAR(10)
  SET @StartMessage = REPLACE(@StartMessage,'%','%%')
  RAISERROR(@StartMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------
  --// Select databases                                                                           //--
  ----------------------------------------------------------------------------------------------------

  IF @Databases IS NULL OR @Databases = ''
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Databases is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  INSERT INTO @tmpDatabases (DatabaseName, Completed)
  SELECT DatabaseName AS DatabaseName,
         0 AS Completed
  FROM dbo.DatabaseSelect (@Databases)
  ORDER BY DatabaseName ASC

  IF @@ERROR <> 0 OR (@@ROWCOUNT = 0 AND @Databases <> 'USER_DATABASES')
  BEGIN
    SET @ErrorMessage = 'Error selecting databases.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Select indexes                                                                             //--
  ----------------------------------------------------------------------------------------------------

  SET @CurrentIndexList = @Indexes

  SET @CurrentIndexList = REPLACE(REPLACE(@CurrentIndexList,'''',''),'"','')

  WHILE CHARINDEX(',,',@CurrentIndexList) > 0 SET @CurrentIndexList = REPLACE(@CurrentIndexList,',,',',')
  WHILE CHARINDEX(', ',@CurrentIndexList) > 0 SET @CurrentIndexList = REPLACE(@CurrentIndexList,', ',',')
  WHILE CHARINDEX(' ,',@CurrentIndexList) > 0 SET @CurrentIndexList = REPLACE(@CurrentIndexList,' ,',',')

  IF RIGHT(@CurrentIndexList,1) = ',' SET @CurrentIndexList = LEFT(@CurrentIndexList,LEN(@CurrentIndexList) - 1)
  IF LEFT(@CurrentIndexList,1) = ',' SET @CurrentIndexList = RIGHT(@CurrentIndexList,LEN(@CurrentIndexList) - 1)

  SET @CurrentIndexList = LTRIM(RTRIM(@CurrentIndexList))

  WHILE LEN(@CurrentIndexList) > 0
  BEGIN
    SET @CurrentIndexPosition = CHARINDEX(',', @CurrentIndexList)
    IF @CurrentIndexPosition = 0
    BEGIN
      SET @CurrentIndexItem = @CurrentIndexList
      SET @CurrentIndexList = ''
    END
    ELSE
    BEGIN
      SET @CurrentIndexItem = LEFT(@CurrentIndexList, @CurrentIndexPosition - 1)
      SET @CurrentIndexList = RIGHT(@CurrentIndexList, LEN(@CurrentIndexList) - @CurrentIndexPosition)
    END;

    WITH IndexItem01 (IndexItem, Selected) AS (
    SELECT CASE WHEN @CurrentIndexItem LIKE '-%' THEN RIGHT(@CurrentIndexItem,LEN(@CurrentIndexItem) - 1) ELSE @CurrentIndexItem END AS IndexItem,
           CASE WHEN @CurrentIndexItem LIKE '-%' THEN 0 ELSE 1 END AS Selected),
    IndexItem02 (IndexItem, Selected) AS (
    SELECT CASE WHEN IndexItem = 'ALL_INDEXES' THEN '%.%.%.%' ELSE IndexItem END AS IndexItem,
           Selected
    FROM IndexItem01)
    INSERT INTO @SelectedIndexes (DatabaseName, SchemaName, ObjectName, IndexName, Selected)
    SELECT DatabaseName = CASE WHEN PARSENAME(IndexItem,4) IS NULL THEN PARSENAME(IndexItem,3) ELSE PARSENAME(IndexItem,4) END,
           SchemaName = CASE WHEN PARSENAME(IndexItem,4) IS NULL THEN PARSENAME(IndexItem,2) ELSE PARSENAME(IndexItem,3) END,
           ObjectName = CASE WHEN PARSENAME(IndexItem,4) IS NULL THEN PARSENAME(IndexItem,1) ELSE PARSENAME(IndexItem,2) END,
           IndexName = CASE WHEN PARSENAME(IndexItem,4) IS NULL THEN '%' ELSE PARSENAME(IndexItem,1) END,
           Selected
    FROM IndexItem02
  END

  IF EXISTS(SELECT * FROM @SelectedIndexes WHERE DatabaseName IS NULL OR SchemaName IS NULL OR ObjectName IS NULL OR IndexName IS NULL) OR (@Indexes IS NOT NULL AND NOT EXISTS(SELECT * FROM @SelectedIndexes))
  BEGIN
    SET @ErrorMessage = 'Error selecting indexes.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END;

  ----------------------------------------------------------------------------------------------------
  --// Select actions                                                                             //--
  ----------------------------------------------------------------------------------------------------

  WITH FragmentationHigh AS
  (
  SELECT CASE WHEN CHARINDEX(',', @FragmentationHigh) = 0 THEN @FragmentationHigh ELSE SUBSTRING(@FragmentationHigh, 1, CHARINDEX(',', @FragmentationHigh) - 1) END AS [Action],
         CASE WHEN CHARINDEX(',', @FragmentationHigh) = 0 THEN '' ELSE SUBSTRING(@FragmentationHigh, CHARINDEX(',', @FragmentationHigh) + 1, LEN(@FragmentationHigh)) END AS String,
         1 AS Priority,
         CASE WHEN CHARINDEX(',', @FragmentationHigh) = 0 THEN 0 ELSE 1 END [Continue]
  WHERE @FragmentationHigh IS NOT NULL
  UNION ALL
  SELECT CASE WHEN CHARINDEX(',', String) = 0 THEN String ELSE SUBSTRING(String, 1, CHARINDEX(',', String) - 1) END AS [Action],
         CASE WHEN CHARINDEX(',', String) = 0 THEN '' ELSE SUBSTRING(String, CHARINDEX(',', String) + 1, LEN(String)) END AS String,
         Priority + 1  AS Priority,
         CASE WHEN CHARINDEX(',', String) = 0 THEN 0 ELSE 1 END [Continue]
  FROM FragmentationHigh
  WHERE [Continue] = 1
  ),
  FragmentationMedium AS
  (
  SELECT CASE WHEN CHARINDEX(',', @FragmentationMedium) = 0 THEN @FragmentationMedium ELSE SUBSTRING(@FragmentationMedium, 1, CHARINDEX(',', @FragmentationMedium) - 1) END AS [Action],
         CASE WHEN CHARINDEX(',', @FragmentationMedium) = 0 THEN '' ELSE SUBSTRING(@FragmentationMedium, CHARINDEX(',', @FragmentationMedium) + 1, LEN(@FragmentationMedium)) END AS String,
         1 AS Priority,
         CASE WHEN CHARINDEX(',', @FragmentationMedium) = 0 THEN 0 ELSE 1 END [Continue]
  WHERE @FragmentationMedium IS NOT NULL
  UNION ALL
  SELECT CASE WHEN CHARINDEX(',', String) = 0 THEN String ELSE SUBSTRING(String, 1, CHARINDEX(',', String) - 1) END AS [Action],
         CASE WHEN CHARINDEX(',', String) = 0 THEN '' ELSE SUBSTRING(String, CHARINDEX(',', String) + 1, LEN(String)) END AS String,
         Priority + 1  AS Priority,
         CASE WHEN CHARINDEX(',', String) = 0 THEN 0 ELSE 1 END [Continue]
  FROM FragmentationMedium
  WHERE [Continue] = 1
  ),
  FragmentationLow AS
  (
  SELECT CASE WHEN CHARINDEX(',', @FragmentationLow) = 0 THEN @FragmentationLow ELSE SUBSTRING(@FragmentationLow, 1, CHARINDEX(',', @FragmentationLow) - 1) END AS [Action],
         CASE WHEN CHARINDEX(',', @FragmentationLow) = 0 THEN '' ELSE SUBSTRING(@FragmentationLow, CHARINDEX(',', @FragmentationLow) + 1, LEN(@FragmentationLow)) END AS String,
         1 AS Priority,
         CASE WHEN CHARINDEX(',', @FragmentationLow) = 0 THEN 0 ELSE 1 END [Continue]
  WHERE @FragmentationLow IS NOT NULL
  UNION ALL
  SELECT CASE WHEN CHARINDEX(',', String) = 0 THEN String ELSE SUBSTRING(String, 1, CHARINDEX(',', String) - 1) END AS [Action],
         CASE WHEN CHARINDEX(',', String) = 0 THEN '' ELSE SUBSTRING(String, CHARINDEX(',', String) + 1, LEN(String)) END AS String,
         Priority + 1  AS Priority,
         CASE WHEN CHARINDEX(',', String) = 0 THEN 0 ELSE 1 END [Continue]
  FROM FragmentationLow
  WHERE [Continue] = 1
  )
  INSERT INTO @ActionsPreferred(FragmentationGroup, Priority, [Action])
  SELECT 'High' AS FragmentationGroup, Priority, [Action]
  FROM FragmentationHigh
  UNION
  SELECT 'Medium' AS FragmentationGroup, Priority, [Action]
  FROM FragmentationMedium
  UNION
  SELECT 'Low' AS FragmentationGroup, Priority, [Action]
  FROM FragmentationLow

  ----------------------------------------------------------------------------------------------------
  --// Check input parameters                                                                     //--
  ----------------------------------------------------------------------------------------------------

  IF EXISTS (SELECT [Action] FROM @ActionsPreferred WHERE FragmentationGroup = 'High' AND [Action] NOT IN(SELECT * FROM @Actions))
  OR EXISTS(SELECT * FROM @ActionsPreferred WHERE FragmentationGroup = 'High' GROUP BY [Action] HAVING COUNT(*) > 1)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @FragmentationHigh is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF EXISTS (SELECT [Action] FROM @ActionsPreferred WHERE FragmentationGroup = 'Medium' AND [Action] NOT IN(SELECT * FROM @Actions))
  OR EXISTS(SELECT * FROM @ActionsPreferred WHERE FragmentationGroup = 'Medium' GROUP BY [Action] HAVING COUNT(*) > 1)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @FragmentationMedium is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF EXISTS (SELECT [Action] FROM @ActionsPreferred WHERE FragmentationGroup = 'Low' AND [Action] NOT IN(SELECT * FROM @Actions))
  OR EXISTS(SELECT * FROM @ActionsPreferred WHERE FragmentationGroup = 'Low' GROUP BY [Action] HAVING COUNT(*) > 1)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @FragmentationLow is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @FragmentationLevel1 <= 0 OR @FragmentationLevel1 >= 100 OR @FragmentationLevel1 >= @FragmentationLevel2 OR @FragmentationLevel1 IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @FragmentationLevel1 is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @FragmentationLevel2 <= 0 OR @FragmentationLevel2 >= 100 OR @FragmentationLevel2 <= @FragmentationLevel1 OR @FragmentationLevel2 IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @FragmentationLevel2 is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @PageCountLevel < 0 OR @PageCountLevel IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @PageCountLevel is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @SortInTempdb NOT IN('Y','N') OR @SortInTempdb IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @SortInTempdb is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @MaxDOP < 0 OR @MaxDOP > 64 OR @MaxDOP > (SELECT cpu_count FROM sys.dm_os_sys_info) OR (@MaxDOP > 1 AND SERVERPROPERTY('EngineEdition') <> 3)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @MaxDOP is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @MaxDOP > 1 AND SERVERPROPERTY('EngineEdition') <> 3
  BEGIN
    SET @ErrorMessage = 'Parallel index operations are only supported in Enterprise, Developer and Datacenter Edition.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @FillFactor <= 0 OR @FillFactor > 100
  BEGIN
    SET @ErrorMessage = 'The value for parameter @FillFactor is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @PadIndex NOT IN('Y','N')
  BEGIN
    SET @ErrorMessage = 'The value for parameter @PadIndex is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @LOBCompaction NOT IN('Y','N') OR @LOBCompaction IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @LOBCompaction is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @UpdateStatistics NOT IN('ALL','COLUMNS','INDEX')
  BEGIN
    SET @ErrorMessage = 'The value for parameter @UpdateStatistics is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @OnlyModifiedStatistics NOT IN('Y','N') OR @OnlyModifiedStatistics IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @OnlyModifiedStatistics is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @StatisticsSample <= 0 OR @StatisticsSample  > 100
  BEGIN
    SET @ErrorMessage = 'The value for parameter @StatisticsSample is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @StatisticsResample NOT IN('Y','N') OR @StatisticsResample IS NULL OR (@StatisticsResample = 'Y' AND @StatisticsSample IS NOT NULL)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @StatisticsResample is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @PartitionLevel NOT IN('Y','N') OR @PartitionLevel IS NULL OR (@PartitionLevel = 'Y' AND SERVERPROPERTY('EngineEdition') <> 3)
  BEGIN
    SET @ErrorMessage = 'The value for parameter @PartitionLevel is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @PartitionLevel = 'Y' AND SERVERPROPERTY('EngineEdition') <> 3
  BEGIN
    SET @ErrorMessage = 'Table partitioning is only supported in Enterprise, Developer and Datacenter Edition.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @TimeLimit < 0
  BEGIN
    SET @ErrorMessage = 'The value for parameter @TimeLimit is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Delay < 0
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Delay is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  IF @Execute NOT IN('Y','N') OR @Execute IS NULL
  BEGIN
    SET @ErrorMessage = 'The value for parameter @Execute is not supported.' + CHAR(13) + CHAR(10)
    RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
    SET @Error = @@ERROR
  END

  ----------------------------------------------------------------------------------------------------
  --// Check error variable                                                                       //--
  ----------------------------------------------------------------------------------------------------

  IF @Error <> 0 GOTO Logging

  ----------------------------------------------------------------------------------------------------
  --// Execute commands                                                                           //--
  ----------------------------------------------------------------------------------------------------

  WHILE EXISTS (SELECT * FROM @tmpDatabases WHERE Completed = 0)
  BEGIN

    SELECT TOP 1 @CurrentID = ID,
                 @CurrentDatabase = DatabaseName
    FROM @tmpDatabases
    WHERE Completed = 0
    ORDER BY ID ASC

    IF EXISTS (SELECT * FROM sys.database_recovery_status WHERE database_id = DB_ID(@CurrentDatabase) AND database_guid IS NOT NULL)
    BEGIN
      SET @CurrentIsDatabaseAccessible = 1
    END
    ELSE
    BEGIN
      SET @CurrentIsDatabaseAccessible = 0
    END

    SELECT @CurrentMirroringRole = mirroring_role_desc
    FROM sys.database_mirroring
    WHERE database_id = DB_ID(@CurrentDatabase)

    -- Set database message
    SET @DatabaseMessage = 'DateTime: ' + CONVERT(nvarchar,GETDATE(),120) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Database: ' + QUOTENAME(@CurrentDatabase) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Status: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Status') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Mirroring role: ' + ISNULL(@CurrentMirroringRole,'None') + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Standby: ' + CASE WHEN DATABASEPROPERTYEX(@CurrentDatabase,'IsInStandBy') = 1 THEN 'Yes' ELSE 'No' END + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Updateability: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Updateability') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'User access: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'UserAccess') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Is accessible: ' + CASE WHEN @CurrentIsDatabaseAccessible = 1 THEN 'Yes' ELSE 'No' END + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = @DatabaseMessage + 'Recovery model: ' + CAST(DATABASEPROPERTYEX(@CurrentDatabase,'Recovery') AS nvarchar) + CHAR(13) + CHAR(10)
    SET @DatabaseMessage = REPLACE(@DatabaseMessage,'%','%%')
    RAISERROR(@DatabaseMessage,10,1) WITH NOWAIT

    IF DATABASEPROPERTYEX(@CurrentDatabase,'Status') = 'ONLINE'
    AND NOT (DATABASEPROPERTYEX(@CurrentDatabase,'UserAccess') = 'SINGLE_USER' AND @CurrentIsDatabaseAccessible = 0)
    AND DATABASEPROPERTYEX(@CurrentDatabase,'Updateability') = 'READ_WRITE'
    BEGIN

      -- Select indexes in the current database
      SET @CurrentCommandSelect01 = 'SELECT SchemaID, SchemaName, ObjectID, ObjectName, ObjectType, IndexID, IndexName, IndexType, StatisticsID, StatisticsName, PartitionID, PartitionNumber, PartitionCount, Selected, Completed FROM (SELECT ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[schema_id] AS SchemaID, ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[name] AS SchemaName, ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[object_id] AS ObjectID, ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[name] AS ObjectName, RTRIM(' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[type]) AS ObjectType, ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.index_id AS IndexID, ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[name] AS IndexName, ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[type] AS IndexType, ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.stats_id AS StatisticsID, ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.name AS StatisticsName'
      IF @PartitionLevel = 'Y' SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ', ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions.partition_id AS PartitionID, ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions.partition_number AS PartitionNumber, IndexPartitions.partition_count AS PartitionCount'
      IF @PartitionLevel = 'N' SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ', NULL AS PartitionID, NULL AS PartitionNumber, NULL AS PartitionCount'
      SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ', 0 AS Selected, 0 AS Completed FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.objects ON ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[object_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[object_id] INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas ON ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[schema_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[schema_id] LEFT OUTER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.stats ON ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[object_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.[object_id] AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[index_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.[stats_id]'
      IF @PartitionLevel = 'Y' SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ' LEFT OUTER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions ON ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[object_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions.[object_id] AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.index_id = ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions.index_id LEFT OUTER JOIN (SELECT [object_id], index_id, COUNT(*) AS partition_count FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions GROUP BY [object_id], index_id) IndexPartitions ON ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions.[object_id] = IndexPartitions.[object_id] AND ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions.[index_id] = IndexPartitions.[index_id]'
      SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ' WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[type] IN(''U'',''V'') AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.is_ms_shipped = 0 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[type] IN(1,2,3,4) AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.is_disabled = 0 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.is_hypothetical = 0'
      IF @UpdateStatistics IN('ALL','COLUMNS') SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ' UNION SELECT ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[schema_id] AS SchemaID, ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[name] AS SchemaName, ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[object_id] AS ObjectID, ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[name] AS ObjectName, RTRIM(' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[type]) AS ObjectType, NULL AS IndexID, NULL AS IndexName, NULL AS IndexType, ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.stats_id AS StatisticsID, ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.name AS StatisticsName, NULL AS PartitionID, NULL AS PartitionNumber, NULL AS PartitionCount, 0 AS Selected, 0 AS Completed FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.stats INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.objects ON ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.[object_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[object_id] INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas ON ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[schema_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[schema_id] WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[type] IN(''U'',''V'') AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.is_ms_shipped = 0 AND NOT EXISTS(SELECT * FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[object_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.[object_id] AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.index_id = ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.stats_id)'
      SET @CurrentCommandSelect01 = @CurrentCommandSelect01 + ') IndexesStatistics ORDER BY SchemaName ASC, ObjectName ASC, CASE WHEN IndexType IS NULL THEN 1 ELSE 0 END ASC, IndexType ASC, IndexName ASC, StatisticsName ASC, PartitionNumber ASC'

      INSERT INTO @tmpIndexesStatistics (SchemaID, SchemaName, ObjectID, ObjectName, ObjectType, IndexID, IndexName, IndexType, StatisticsID, StatisticsName, PartitionID, PartitionNumber, PartitionCount, Selected, Completed)
      EXECUTE(@CurrentCommandSelect01)
      SET @Error = @@ERROR
      IF @Error = 1222
      BEGIN
        SET @ErrorMessage = 'The system tables are locked in the database ' + QUOTENAME(@CurrentDatabase) + '.' + CHAR(13) + CHAR(10)
        SET @ErrorMessage = REPLACE(@ErrorMessage,'%','%%')
        RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
      END

      IF @Indexes IS NULL
      BEGIN
        UPDATE tmpIndexesStatistics
        SET tmpIndexesStatistics.Selected = 1
        FROM @tmpIndexesStatistics tmpIndexesStatistics
      END
      ELSE
      BEGIN
        UPDATE tmpIndexesStatistics
        SET tmpIndexesStatistics.Selected = SelectedIndexes.Selected
        FROM @tmpIndexesStatistics tmpIndexesStatistics
        INNER JOIN @SelectedIndexes SelectedIndexes
        ON @CurrentDatabase LIKE REPLACE(SelectedIndexes.DatabaseName,'_','[_]') AND tmpIndexesStatistics.SchemaName LIKE REPLACE(SelectedIndexes.SchemaName,'_','[_]') AND tmpIndexesStatistics.ObjectName LIKE REPLACE(SelectedIndexes.ObjectName,'_','[_]') AND COALESCE(tmpIndexesStatistics.IndexName,tmpIndexesStatistics.StatisticsName) LIKE REPLACE(SelectedIndexes.IndexName,'_','[_]')
        WHERE SelectedIndexes.Selected = 1

        UPDATE tmpIndexesStatistics
        SET tmpIndexesStatistics.Selected = SelectedIndexes.Selected
        FROM @tmpIndexesStatistics tmpIndexesStatistics
        INNER JOIN @SelectedIndexes SelectedIndexes
        ON @CurrentDatabase LIKE REPLACE(SelectedIndexes.DatabaseName,'_','[_]') AND tmpIndexesStatistics.SchemaName LIKE REPLACE(SelectedIndexes.SchemaName,'_','[_]') AND tmpIndexesStatistics.ObjectName LIKE REPLACE(SelectedIndexes.ObjectName,'_','[_]') AND COALESCE(tmpIndexesStatistics.IndexName,tmpIndexesStatistics.StatisticsName) LIKE REPLACE(SelectedIndexes.IndexName,'_','[_]')
        WHERE SelectedIndexes.Selected = 0
      END

      WHILE EXISTS (SELECT * FROM @tmpIndexesStatistics WHERE Selected = 1 AND Completed = 0)
      BEGIN

        SELECT TOP 1 @CurrentIxID = IxID,
                     @CurrentSchemaID = SchemaID,
                     @CurrentSchemaName = SchemaName,
                     @CurrentObjectID = ObjectID,
                     @CurrentObjectName = ObjectName,
                     @CurrentObjectType = ObjectType,
                     @CurrentIndexID = IndexID,
                     @CurrentIndexName = IndexName,
                     @CurrentIndexType = IndexType,
                     @CurrentStatisticsID = StatisticsID,
                     @CurrentStatisticsName = StatisticsName,
                     @CurrentPartitionID = PartitionID,
                     @CurrentPartitionNumber = PartitionNumber,
                     @CurrentPartitionCount = PartitionCount
        FROM @tmpIndexesStatistics
        WHERE Selected = 1
        AND Completed = 0
        ORDER BY IxID ASC

        -- Is the index a partition?
        IF @CurrentPartitionNumber IS NULL OR @CurrentPartitionCount = 1 BEGIN SET @CurrentIsPartition = 0 END ELSE BEGIN SET @CurrentIsPartition = 1 END

        -- Does the index exist?
        IF @CurrentIndexID IS NOT NULL
        BEGIN
          IF @CurrentIsPartition = 0 SET @CurrentCommandSelect02 = 'SELECT COUNT(*) FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.objects ON ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[object_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[object_id] INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas ON ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[schema_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[schema_id] WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[type] IN(''U'',''V'') AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.is_ms_shipped = 0 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[type] IN(1,2,3,4) AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.is_disabled = 0 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.is_hypothetical = 0 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[schema_id] = ' + CAST(@CurrentSchemaID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[name] = N' + QUOTENAME(@CurrentSchemaName,'''') + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[object_id] = ' + CAST(@CurrentObjectID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[name] = N' + QUOTENAME(@CurrentObjectName,'''') + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[type] = N' + QUOTENAME(@CurrentObjectType,'''') + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.index_id = ' + CAST(@CurrentIndexID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[name] = N' + QUOTENAME(@CurrentIndexName,'''') + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[type] = ' + CAST(@CurrentIndexType AS nvarchar)
          IF @CurrentIsPartition = 1 SET @CurrentCommandSelect02 = 'SELECT COUNT(*) FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.objects ON ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[object_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[object_id] INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas ON ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[schema_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[schema_id] INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions ON ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[object_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions.[object_id] AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.index_id = ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions.index_id WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[type] IN(''U'',''V'') AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.is_ms_shipped = 0 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[type] IN(1,2,3,4) AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.is_disabled = 0 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.is_hypothetical = 0 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[schema_id] = ' + CAST(@CurrentSchemaID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[name] = N' + QUOTENAME(@CurrentSchemaName,'''') + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[object_id] = ' + CAST(@CurrentObjectID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[name] = N' + QUOTENAME(@CurrentObjectName,'''') + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[type] = N' + QUOTENAME(@CurrentObjectType,'''') + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.index_id = ' + CAST(@CurrentIndexID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[name] = N' + QUOTENAME(@CurrentIndexName,'''') + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[type] = ' + CAST(@CurrentIndexType AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions.partition_id = ' + CAST(@CurrentPartitionID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.partitions.partition_number = ' + CAST(@CurrentPartitionNumber AS nvarchar)

          INSERT INTO @tmpIndexExists ([Count])
          EXECUTE(@CurrentCommandSelect02)

          IF (SELECT [Count] FROM @tmpIndexExists) > 0 BEGIN SET @CurrentIndexExists = 1 END ELSE BEGIN SET @CurrentIndexExists = 0 END

          IF @CurrentIndexExists = 0 GOTO NoAction
        END

        -- Does the statistics exist?
        IF @CurrentStatisticsID IS NOT NULL
        BEGIN
          SET @CurrentCommandSelect06 = 'SELECT COUNT(*) FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.stats INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.objects ON ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.[object_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[object_id] INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas ON ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[schema_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[schema_id] WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[type] IN(''U'',''V'') AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.is_ms_shipped = 0 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[schema_id] = ' + CAST(@CurrentSchemaID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.schemas.[name] = N' + QUOTENAME(@CurrentSchemaName,'''') + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[object_id] = ' + CAST(@CurrentObjectID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[name] = N' + QUOTENAME(@CurrentObjectName,'''') + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.objects.[type] = N' + QUOTENAME(@CurrentObjectType,'''') + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.stats_id = ' + CAST(@CurrentStatisticsID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.[name] = N' + QUOTENAME(@CurrentStatisticsName,'''')

          INSERT INTO @tmpStatisticsExists ([Count])
          EXECUTE(@CurrentCommandSelect06)

          IF (SELECT [Count] FROM @tmpStatisticsExists) > 0 BEGIN SET @CurrentStatisticsExists = 1 END ELSE BEGIN SET @CurrentStatisticsExists = 0 END

          IF @CurrentStatisticsExists = 0 GOTO NoAction
        END

        -- Does the index contain a LOB?
        IF @CurrentIndexID IS NOT NULL AND @CurrentIndexType IN(1,2)
        BEGIN
          IF @CurrentIndexType = 1 SET @CurrentCommandSelect03 = 'SELECT COUNT(*) FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.columns INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.types ON ' + QUOTENAME(@CurrentDatabase) + '.sys.columns.system_type_id = ' + QUOTENAME(@CurrentDatabase) + '.sys.types.user_type_id OR (' + QUOTENAME(@CurrentDatabase) + '.sys.columns.user_type_id = ' + QUOTENAME(@CurrentDatabase) + '.sys.types.user_type_id AND '+ QUOTENAME(@CurrentDatabase) + '.sys.types.is_assembly_type = 1) WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.columns.[object_id] = ' + CAST(@CurrentObjectID AS nvarchar) + ' AND (' + QUOTENAME(@CurrentDatabase) + '.sys.types.name IN(''xml'',''image'',''text'',''ntext'') OR (' + QUOTENAME(@CurrentDatabase) + '.sys.types.name IN(''varchar'',''nvarchar'',''varbinary'') AND ' + QUOTENAME(@CurrentDatabase) + '.sys.columns.max_length = -1) OR (' + QUOTENAME(@CurrentDatabase) + '.sys.types.is_assembly_type = 1 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.columns.max_length = -1))'
          IF @CurrentIndexType = 2 SET @CurrentCommandSelect03 = 'SELECT COUNT(*) FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.index_columns INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.columns ON ' + QUOTENAME(@CurrentDatabase) + '.sys.index_columns.[object_id] = ' + QUOTENAME(@CurrentDatabase) + '.sys.columns.[object_id] AND ' + QUOTENAME(@CurrentDatabase) + '.sys.index_columns.column_id = ' + QUOTENAME(@CurrentDatabase) + '.sys.columns.column_id INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.types ON ' + QUOTENAME(@CurrentDatabase) + '.sys.columns.system_type_id = ' + QUOTENAME(@CurrentDatabase) + '.sys.types.user_type_id OR (' + QUOTENAME(@CurrentDatabase) + '.sys.columns.user_type_id = ' + QUOTENAME(@CurrentDatabase) + '.sys.types.user_type_id AND ' + QUOTENAME(@CurrentDatabase) + '.sys.types.is_assembly_type = 1) WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.index_columns.[object_id] = ' + CAST(@CurrentObjectID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.index_columns.index_id = ' + CAST(@CurrentIndexID AS nvarchar) + ' AND (' + QUOTENAME(@CurrentDatabase) + '.sys.types.[name] IN(''xml'',''image'',''text'',''ntext'') OR (' + QUOTENAME(@CurrentDatabase) + '.sys.types.[name] IN(''varchar'',''nvarchar'',''varbinary'') AND ' + QUOTENAME(@CurrentDatabase) + '.sys.columns.max_length = -1) OR (' + QUOTENAME(@CurrentDatabase) + '.sys.types.is_assembly_type = 1 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.columns.max_length = -1))'

          INSERT INTO @tmpIsLOB ([Count])
          EXECUTE(@CurrentCommandSelect03)

          IF (SELECT [Count] FROM @tmpIsLOB) > 0 BEGIN SET @CurrentIsLOB = 1 END ELSE BEGIN SET @CurrentIsLOB = 0 END
        END

        -- Is Allow_Page_Locks set to On?
        IF @CurrentIndexID IS NOT NULL
        BEGIN
          SET @CurrentCommandSelect04 = 'SELECT COUNT(*) FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[object_id] = ' + CAST(@CurrentObjectID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[index_id] = ' + CAST(@CurrentIndexID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[allow_page_locks] = 1'

          INSERT INTO @tmpAllowPageLocks ([Count])
          EXECUTE(@CurrentCommandSelect04)

          IF (SELECT [Count] FROM @tmpAllowPageLocks) > 0 BEGIN SET @CurrentAllowPageLocks = 1 END ELSE BEGIN SET @CurrentAllowPageLocks = 0 END
        END

        -- Is No_Recompute set to On?
        IF @CurrentStatisticsID IS NOT NULL
        BEGIN
          SET @CurrentCommandSelect07 = 'SELECT COUNT(*) FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.stats WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.[object_id] = ' + CAST(@CurrentObjectID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.[stats_id] = ' + CAST(@CurrentStatisticsID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.stats.[no_recompute] = 1'

          INSERT INTO @tmpNoRecompute ([Count])
          EXECUTE(@CurrentCommandSelect07)

          IF (SELECT [Count] FROM @tmpNoRecompute) > 0 BEGIN SET @CurrentNoRecompute = 1 END ELSE BEGIN SET @CurrentNoRecompute = 0 END
        END

        -- Has the data in the statistics been modified since the statistics was last updated?
        IF @CurrentStatisticsID IS NOT NULL
        BEGIN
          SET @CurrentCommandSelect08 = 'SELECT COUNT(*) FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.sysindexes WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.sysindexes.[id] = ' + CAST(@CurrentObjectID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.sysindexes.[indid] = ' + CAST(@CurrentStatisticsID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.sysindexes.[rowmodctr] <> 0'

          INSERT INTO @tmpStatisticsModified ([Count])
          EXECUTE(@CurrentCommandSelect08)

          IF (SELECT [Count] FROM @tmpStatisticsModified) > 0 BEGIN SET @CurrentStatisticsModified = 1 END ELSE BEGIN SET @CurrentStatisticsModified = 0 END
        END

        -- Is the index on a read-only filegroup?
        IF @CurrentIndexID IS NOT NULL
        BEGIN
          SET @CurrentCommandSelect05 = 'SELECT COUNT(*) FROM (SELECT ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups.data_space_id FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.destination_data_spaces ON ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.data_space_id = ' + QUOTENAME(@CurrentDatabase) + '.sys.destination_data_spaces.partition_scheme_id INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups ON ' + QUOTENAME(@CurrentDatabase) + '.sys.destination_data_spaces.data_space_id = ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups.data_space_id WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups.is_read_only = 1 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[object_id] = ' + CAST(@CurrentObjectID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[index_id] = ' + CAST(@CurrentIndexID AS nvarchar)
          IF @CurrentIsPartition = 1 SET @CurrentCommandSelect05 = @CurrentCommandSelect05 + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.destination_data_spaces.destination_id = ' + CAST(@CurrentPartitionNumber AS nvarchar)
          SET @CurrentCommandSelect05 = @CurrentCommandSelect05 + ' UNION SELECT ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups.data_space_id FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups ON ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.data_space_id = ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups.data_space_id WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups.is_read_only = 1 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[object_id] = ' + CAST(@CurrentObjectID AS nvarchar) + ' AND ' + QUOTENAME(@CurrentDatabase) + '.sys.indexes.[index_id] = ' + CAST(@CurrentIndexID AS nvarchar)
          IF @CurrentIndexType = 1 SET @CurrentCommandSelect05 = @CurrentCommandSelect05 + ' UNION SELECT ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups.data_space_id FROM ' + QUOTENAME(@CurrentDatabase) + '.sys.tables INNER JOIN ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups ON ' + QUOTENAME(@CurrentDatabase) + '.sys.tables.lob_data_space_id = ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups.data_space_id WHERE ' + QUOTENAME(@CurrentDatabase) + '.sys.filegroups.is_read_only = 1 AND ' + QUOTENAME(@CurrentDatabase) + '.sys.tables.[object_id] = ' + CAST(@CurrentObjectID AS nvarchar)
          SET @CurrentCommandSelect05 = @CurrentCommandSelect05 + ') ReadOnlyFileGroups'

          INSERT INTO @tmpOnReadOnlyFileGroup ([Count])
          EXECUTE(@CurrentCommandSelect05)

          IF (SELECT [Count] FROM @tmpOnReadOnlyFileGroup) > 0 BEGIN SET @CurrentOnReadOnlyFileGroup = 1 END ELSE BEGIN SET @CurrentOnReadOnlyFileGroup = 0 END
        END

        -- Is the index fragmented?
        IF @CurrentIndexID IS NOT NULL
        AND EXISTS(SELECT * FROM @ActionsPreferred)
        AND (EXISTS(SELECT Priority, [Action], COUNT(*) FROM @ActionsPreferred GROUP BY Priority, [Action] HAVING COUNT(*) <> 3) OR @PageCountLevel > 0)
        BEGIN
          SELECT @CurrentFragmentationLevel = MAX(avg_fragmentation_in_percent),
                 @CurrentPageCount = SUM(page_count)
          FROM sys.dm_db_index_physical_stats(DB_ID(@CurrentDatabase), @CurrentObjectID, @CurrentIndexID, @CurrentPartitionNumber, 'LIMITED')
          WHERE alloc_unit_type_desc = 'IN_ROW_DATA'
          AND index_level = 0
          SET @Error = @@ERROR
          IF @Error = 1222
          BEGIN
            SET @ErrorMessage = 'The dynamic management view sys.dm_db_index_physical_stats is locked on the index ' + QUOTENAME(@CurrentSchemaName) + '.' + QUOTENAME(@CurrentObjectName) + '.' + QUOTENAME(@CurrentIndexName) + '.' + CHAR(13) + CHAR(10)
            SET @ErrorMessage = REPLACE(@ErrorMessage,'%','%%')
            RAISERROR(@ErrorMessage,16,1) WITH NOWAIT
            GOTO NoAction
          END
        END

        -- Select fragmentation group
        IF @CurrentIndexID IS NOT NULL
        BEGIN
          SET @CurrentFragmentationGroup = CASE
          WHEN @CurrentFragmentationLevel >= @FragmentationLevel2 THEN 'High'
          WHEN @CurrentFragmentationLevel >= @FragmentationLevel1 AND @CurrentFragmentationLevel < @FragmentationLevel2 THEN 'Medium'
          WHEN @CurrentFragmentationLevel < @FragmentationLevel1 THEN 'Low'
          END
        END

        -- Which actions are allowed?
        IF @CurrentIndexID IS NOT NULL
        BEGIN
          IF @CurrentOnReadOnlyFileGroup = 0 AND @CurrentAllowPageLocks = 1
          BEGIN
            INSERT INTO @CurrentActionsAllowed ([Action])
            VALUES ('INDEX_REORGANIZE')
          END
          IF @CurrentOnReadOnlyFileGroup = 0
          BEGIN
            INSERT INTO @CurrentActionsAllowed ([Action])
            VALUES ('INDEX_REBUILD_OFFLINE')
          END
          IF @CurrentOnReadOnlyFileGroup = 0 AND @CurrentIndexType IN(1,2) AND @CurrentIsLOB = 0 AND @CurrentIsPartition = 0 AND SERVERPROPERTY('EngineEdition') = 3
          BEGIN
            INSERT INTO @CurrentActionsAllowed ([Action])
            VALUES ('INDEX_REBUILD_ONLINE')
          END
        END

        -- Decide action
        IF @CurrentIndexID IS NOT NULL
        AND EXISTS(SELECT * FROM @ActionsPreferred)
        AND (@CurrentPageCount >= @PageCountLevel OR @PageCountLevel = 0)
        BEGIN
          IF EXISTS(SELECT Priority, [Action], COUNT(*) FROM @ActionsPreferred GROUP BY Priority, [Action] HAVING COUNT(*) <> 3)
          BEGIN
            SELECT @CurrentAction = [Action]
            FROM @ActionsPreferred
            WHERE FragmentationGroup = @CurrentFragmentationGroup
            AND Priority = (SELECT MIN(Priority)
                            FROM @ActionsPreferred
                            WHERE FragmentationGroup = @CurrentFragmentationGroup
                            AND [Action] IN (SELECT [Action] FROM @CurrentActionsAllowed))
          END
          ELSE
          BEGIN
            SELECT @CurrentAction = [Action]
            FROM @ActionsPreferred
            WHERE Priority = (SELECT MIN(Priority)
                              FROM @ActionsPreferred
                              WHERE [Action] IN (SELECT [Action] FROM @CurrentActionsAllowed))
          END
        END

        -- Workaround for a bug in SQL Server 2005, SQL Server 2008 and SQL Server 2008 R2
        IF @CurrentIndexID IS NOT NULL
        BEGIN
          SET @CurrentMaxDOP = @MaxDOP
          IF @Version < 11 AND @CurrentAction = 'INDEX_REBUILD_ONLINE' AND @CurrentAllowPageLocks = 0
          BEGIN
            SET @CurrentMaxDOP = 1
          END
        END

        -- Update statistics?
        IF @CurrentStatisticsID IS NOT NULL
        AND (@UpdateStatistics = 'ALL' OR (@UpdateStatistics = 'INDEX' AND @CurrentIndexID IS NOT NULL) OR (@UpdateStatistics = 'COLUMNS' AND @CurrentIndexID IS NULL))
        AND (@CurrentStatisticsModified = 1 OR @OnlyModifiedStatistics = 'N')
        AND ((@CurrentIsPartition = 0 AND (@CurrentAction NOT IN('INDEX_REBUILD_ONLINE','INDEX_REBUILD_OFFLINE') OR @CurrentAction IS NULL)) OR (@CurrentIsPartition = 1 AND @CurrentPartitionNumber = @CurrentPartitionCount))
        BEGIN
          SET @CurrentUpdateStatistics = 'Y'
        END
        ELSE
        BEGIN
          SET @CurrentUpdateStatistics = 'N'
        END

        -- Create comment
        IF @CurrentIndexID IS NOT NULL
        BEGIN
          SET @CurrentComment = 'ObjectType: ' + CASE WHEN @CurrentObjectType = 'U' THEN 'Table' WHEN @CurrentObjectType = 'V' THEN 'View' ELSE 'N/A' END + ', '
          SET @CurrentComment = @CurrentComment + 'IndexType: ' + CASE WHEN @CurrentIndexType = 1 THEN 'Clustered' WHEN @CurrentIndexType = 2 THEN 'NonClustered' WHEN @CurrentIndexType = 3 THEN 'XML' WHEN @CurrentIndexType = 4 THEN 'Spatial' ELSE 'N/A' END + ', '
          SET @CurrentComment = @CurrentComment + 'LOB: ' + CASE WHEN @CurrentIsLOB = 1 THEN 'Yes' WHEN @CurrentIsLOB = 0 THEN 'No' ELSE 'N/A' END + ', '
          SET @CurrentComment = @CurrentComment + 'AllowPageLocks: ' + CASE WHEN @CurrentAllowPageLocks = 1 THEN 'Yes' WHEN @CurrentAllowPageLocks = 0 THEN 'No' ELSE 'N/A' END + ', '
          SET @CurrentComment = @CurrentComment + 'PageCount: ' + ISNULL(CAST(@CurrentPageCount AS nvarchar),'N/A') + ', '
          SET @CurrentComment = @CurrentComment + 'Fragmentation: ' + ISNULL(CAST(@CurrentFragmentationLevel AS nvarchar),'N/A')
        END

        -- Check time limit
        IF GETDATE() >= DATEADD(ss,@TimeLimit,@StartTime)
        BEGIN
          SET @Execute = 'N'
        END

        IF @CurrentIndexID IS NOT NULL AND @CurrentAction IS NOT NULL
        BEGIN
          SET @CurrentCommand01 = 'ALTER INDEX ' + QUOTENAME(@CurrentIndexName) + ' ON ' + QUOTENAME(@CurrentDatabase) + '.' + QUOTENAME(@CurrentSchemaName) + '.' + QUOTENAME(@CurrentObjectName)

          IF @CurrentAction IN('INDEX_REBUILD_ONLINE','INDEX_REBUILD_OFFLINE')
          BEGIN
            SET @CurrentCommand01 = @CurrentCommand01 + ' REBUILD'
            IF @CurrentIsPartition = 1 SET @CurrentCommand01 = @CurrentCommand01 + ' PARTITION = ' + CAST(@CurrentPartitionNumber AS nvarchar)
            SET @CurrentCommand01 = @CurrentCommand01 + ' WITH ('
            IF @SortInTempdb = 'Y' SET @CurrentCommand01 = @CurrentCommand01 + 'SORT_IN_TEMPDB = ON'
            IF @SortInTempdb = 'N' SET @CurrentCommand01 = @CurrentCommand01 + 'SORT_IN_TEMPDB = OFF'
            IF @CurrentAction = 'INDEX_REBUILD_ONLINE' AND @CurrentIsPartition = 0 SET @CurrentCommand01 = @CurrentCommand01 + ', ONLINE = ON'
            IF @CurrentAction = 'INDEX_REBUILD_OFFLINE' AND @CurrentIsPartition = 0 SET @CurrentCommand01 = @CurrentCommand01 + ', ONLINE = OFF'
            IF @CurrentMaxDOP IS NOT NULL SET @CurrentCommand01 = @CurrentCommand01 + ', MAXDOP = ' + CAST(@CurrentMaxDOP AS nvarchar)
            IF @FillFactor IS NOT NULL AND @CurrentIsPartition = 0 SET @CurrentCommand01 = @CurrentCommand01 + ', FILLFACTOR = ' + CAST(@FillFactor AS nvarchar)
            IF @PadIndex = 'Y' AND @CurrentIsPartition = 0 SET @CurrentCommand01 = @CurrentCommand01 + ', PAD_INDEX = ON'
            IF @PadIndex = 'N' AND @CurrentIsPartition = 0 SET @CurrentCommand01 = @CurrentCommand01 + ', PAD_INDEX = OFF'
            SET @CurrentCommand01 = @CurrentCommand01 + ')'
          END

          IF @CurrentAction IN('INDEX_REORGANIZE')
          BEGIN
            SET @CurrentCommand01 = @CurrentCommand01 + ' REORGANIZE'
            IF @CurrentIsPartition = 1 SET @CurrentCommand01 = @CurrentCommand01 + ' PARTITION = ' + CAST(@CurrentPartitionNumber AS nvarchar)
            SET @CurrentCommand01 = @CurrentCommand01 + ' WITH ('
            IF @LOBCompaction = 'Y' SET @CurrentCommand01 = @CurrentCommand01 + 'LOB_COMPACTION = ON'
            IF @LOBCompaction = 'N' SET @CurrentCommand01 = @CurrentCommand01 + 'LOB_COMPACTION = OFF'
            SET @CurrentCommand01 = @CurrentCommand01 + ')'
          END

          EXECUTE @CurrentCommandOutput01 = [dbo].[CommandExecute] @CurrentCommand01, @CurrentComment, 2, @Execute
          SET @Error = @@ERROR
          IF @Error <> 0 SET @CurrentCommandOutput01 = @Error

          IF @CurrentDelay IS NOT NULL
          BEGIN
            WAITFOR DELAY @CurrentDelay
          END
        END

        IF @CurrentStatisticsID IS NOT NULL AND @CurrentUpdateStatistics = 'Y'
        BEGIN
          SET @CurrentCommand02 = 'UPDATE STATISTICS ' + QUOTENAME(@CurrentDatabase) + '.' + QUOTENAME(@CurrentSchemaName) + '.' + QUOTENAME(@CurrentObjectName) + ' ' + QUOTENAME(@CurrentStatisticsName)
          IF @StatisticsSample IS NOT NULL OR @StatisticsResample = 'Y' OR @CurrentNoRecompute = 1 SET @CurrentCommand02 = @CurrentCommand02 + ' WITH'
          IF @StatisticsSample = 100 SET @CurrentCommand02 = @CurrentCommand02 + ' FULLSCAN'
          IF @StatisticsSample IS NOT NULL AND @StatisticsSample <> 100 SET @CurrentCommand02 = @CurrentCommand02 + ' SAMPLE ' + CAST(@StatisticsSample AS nvarchar) + ' PERCENT'
          IF @StatisticsResample = 'Y' SET @CurrentCommand02 = @CurrentCommand02 + ' RESAMPLE'
          IF (@StatisticsSample IS NOT NULL OR @StatisticsResample = 'Y') AND @CurrentNoRecompute = 1 SET @CurrentCommand02 = @CurrentCommand02 + ','
          IF @CurrentNoRecompute = 1 SET @CurrentCommand02 = @CurrentCommand02 + ' NORECOMPUTE'

          EXECUTE @CurrentCommandOutput02 = [dbo].[CommandExecute] @CurrentCommand02, '', 2, @Execute
          SET @Error = @@ERROR
          IF @Error <> 0 SET @CurrentCommandOutput02 = @Error
        END

        NoAction:

        -- Update that the index is completed
        UPDATE @tmpIndexesStatistics
        SET Completed = 1
        WHERE IxID = @CurrentIxID

        -- Clear variables
        SET @CurrentCommandSelect02 = NULL
        SET @CurrentCommandSelect03 = NULL
        SET @CurrentCommandSelect04 = NULL
        SET @CurrentCommandSelect05 = NULL
        SET @CurrentCommandSelect06 = NULL
        SET @CurrentCommandSelect07 = NULL
        SET @CurrentCommandSelect08 = NULL

        SET @CurrentCommand01 = NULL
        SET @CurrentCommand02 = NULL

        SET @CurrentCommandOutput01 = NULL
        SET @CurrentCommandOutput02 = NULL

        SET @CurrentIxID = NULL
        SET @CurrentSchemaID = NULL
        SET @CurrentSchemaName = NULL
        SET @CurrentObjectID = NULL
        SET @CurrentObjectName = NULL
        SET @CurrentObjectType = NULL
        SET @CurrentIndexID = NULL
        SET @CurrentIndexName = NULL
        SET @CurrentIndexType = NULL
        SET @CurrentStatisticsID = NULL
        SET @CurrentStatisticsName = NULL
        SET @CurrentPartitionID = NULL
        SET @CurrentPartitionNumber = NULL
        SET @CurrentPartitionCount = NULL
        SET @CurrentIsPartition = NULL
        SET @CurrentIndexExists = NULL
        SET @CurrentStatisticsExists = NULL
        SET @CurrentIsLOB = NULL
        SET @CurrentAllowPageLocks = NULL
        SET @CurrentNoRecompute = NULL
        SET @CurrentStatisticsModified = NULL
        SET @CurrentOnReadOnlyFileGroup = NULL
        SET @CurrentFragmentationLevel = NULL
        SET @CurrentPageCount = NULL
        SET @CurrentFragmentationGroup = NULL
        SET @CurrentAction = NULL
        SET @CurrentMaxDOP = NULL
        SET @CurrentUpdateStatistics = NULL
        SET @CurrentComment = NULL

        DELETE FROM @tmpIndexExists
        DELETE FROM @tmpStatisticsExists
        DELETE FROM @tmpIsLOB
        DELETE FROM @tmpAllowPageLocks
        DELETE FROM @tmpNoRecompute
        DELETE FROM @tmpStatisticsModified
        DELETE FROM @tmpOnReadOnlyFileGroup
        DELETE FROM @CurrentActionsAllowed

      END

    END

    -- Update that the database is completed
    UPDATE @tmpDatabases
    SET Completed = 1
    WHERE ID = @CurrentID

    -- Clear variables
    SET @CurrentID = NULL
    SET @CurrentDatabase = NULL
    SET @CurrentIsDatabaseAccessible = NULL
    SET @CurrentMirroringRole = NULL

    SET @CurrentCommandSelect01 = NULL

    DELETE FROM @tmpIndexesStatistics

  END

  ----------------------------------------------------------------------------------------------------
  --// Log completing information                                                                 //--
  ----------------------------------------------------------------------------------------------------

  Logging:
  SET @EndMessage = 'DateTime: ' + CONVERT(nvarchar,GETDATE(),120)
  SET @EndMessage = REPLACE(@EndMessage,'%','%%')
  RAISERROR(@EndMessage,10,1) WITH NOWAIT

  ----------------------------------------------------------------------------------------------------

END
GO

IF (SELECT CAST([Value] AS nvarchar) FROM #Config WHERE Name = 'Error') <> '0' OR (SELECT [Value] FROM #Config WHERE Name = 'Jobs') <> 'Y' OR SERVERPROPERTY('EngineEdition') = 4
BEGIN
  RETURN
END

DECLARE @LogDirectory nvarchar(max)
DECLARE @BackupDirectory nvarchar(max)
DECLARE @Database nvarchar(max)

DECLARE @Version numeric(18,10)

DECLARE @TokenServer nvarchar(max)
DECLARE @TokenJobID nvarchar(max)
DECLARE @TokenStepID nvarchar(max)
DECLARE @TokenDate nvarchar(max)
DECLARE @TokenTime nvarchar(max)

DECLARE @JobName01 nvarchar(max)
DECLARE @JobName02 nvarchar(max)
DECLARE @JobName03 nvarchar(max)
DECLARE @JobName04 nvarchar(max)
DECLARE @JobName05 nvarchar(max)
DECLARE @JobName06 nvarchar(max)
DECLARE @JobName07 nvarchar(max)
DECLARE @JobName08 nvarchar(max)
DECLARE @JobName09 nvarchar(max)
DECLARE @JobName10 nvarchar(max)

DECLARE @JobCommand01 nvarchar(max)
DECLARE @JobCommand02 nvarchar(max)
DECLARE @JobCommand03 nvarchar(max)
DECLARE @JobCommand04 nvarchar(max)
DECLARE @JobCommand05 nvarchar(max)
DECLARE @JobCommand06 nvarchar(max)
DECLARE @JobCommand07 nvarchar(max)
DECLARE @JobCommand08 nvarchar(max)
DECLARE @JobCommand09 nvarchar(max)
DECLARE @JobCommand10 nvarchar(max)

DECLARE @OutputFile01 nvarchar(max)
DECLARE @OutputFile02 nvarchar(max)
DECLARE @OutputFile03 nvarchar(max)
DECLARE @OutputFile04 nvarchar(max)
DECLARE @OutputFile05 nvarchar(max)
DECLARE @OutputFile06 nvarchar(max)
DECLARE @OutputFile07 nvarchar(max)
DECLARE @OutputFile08 nvarchar(max)
DECLARE @OutputFile09 nvarchar(max)
DECLARE @OutputFile10 nvarchar(max)

SET @Version = CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)),CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - 1) + '.' + REPLACE(RIGHT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)), LEN(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)))),'.','') AS numeric(18,10))

IF @Version >= 9.002047
BEGIN
  SET @TokenServer = '$' + '(ESCAPE_SQUOTE(SRVR))'
  SET @TokenJobID = '$' + '(ESCAPE_SQUOTE(JOBID))'
  SET @TokenStepID = '$' + '(ESCAPE_SQUOTE(STEPID))'
  SET @TokenDate = '$' + '(ESCAPE_SQUOTE(STRTDT))'
  SET @TokenTime = '$' + '(ESCAPE_SQUOTE(STRTTM))'
END
ELSE
BEGIN
  SET @TokenServer = '$' + '(SRVR)'
  SET @TokenJobID = '$' + '(JOBID)'
  SET @TokenStepID = '$' + '(STEPID)'
  SET @TokenDate = '$' + '(STRTDT)'
  SET @TokenTime = '$' + '(STRTTM)'
END

SELECT @LogDirectory = Value
FROM #Config
WHERE [Name] = 'LogDirectory'

SELECT @BackupDirectory = Value
FROM #Config
WHERE [Name] = 'BackupDirectory'

SELECT @Database = Value
FROM #Config
WHERE [Name] = 'Database'

SET @JobName01 = 'DatabaseBackup - SYSTEM_DATABASES - FULL'
SET @JobCommand01 = 'sqlcmd -E -S ' + @TokenServer + ' -d ' + @Database + ' -Q "EXECUTE [dbo].[DatabaseBackup] @Databases = ''SYSTEM_DATABASES'', @Directory = ' + ISNULL('N''' + REPLACE(@BackupDirectory,'''','''''') + '''','NULL') + ', @BackupType = ''FULL'', @Verify = ''Y'', @CleanupTime = 120, @CheckSum = ''Y''" -b'
SET @OutputFile01 = @LogDirectory + '\DatabaseBackup_' + @TokenJobID + '_' + @TokenStepID + '_' + @TokenDate + '_' + @TokenTime + '.txt'

SET @JobName02 = 'DatabaseBackup - USER_DATABASES - DIFF'
SET @JobCommand02 = 'sqlcmd -E -S ' + @TokenServer + ' -d ' + @Database + ' -Q "EXECUTE [dbo].[DatabaseBackup] @Databases = ''USER_DATABASES'', @Directory = ' + ISNULL('N''' + REPLACE(@BackupDirectory,'''','''''') + '''','NULL') + ', @BackupType = ''DIFF'', @Verify = ''Y'', @CleanupTime = 120, @CheckSum = ''Y''" -b'
SET @OutputFile02 = @LogDirectory + '\DatabaseBackup_' + @TokenJobID + '_' + @TokenStepID + '_' + @TokenDate + '_' + @TokenTime + '.txt'

SET @JobName03 = 'DatabaseBackup - USER_DATABASES - FULL'
SET @JobCommand03 = 'sqlcmd -E -S ' + @TokenServer + ' -d ' + @Database + ' -Q "EXECUTE [dbo].[DatabaseBackup] @Databases = ''USER_DATABASES'', @Directory = ' + ISNULL('N''' + REPLACE(@BackupDirectory,'''','''''') + '''','NULL') + ', @BackupType = ''FULL'', @Verify = ''Y'', @CleanupTime = 120, @CheckSum = ''Y''" -b'
SET @OutputFile03 = @LogDirectory + '\DatabaseBackup_' + @TokenJobID + '_' + @TokenStepID + '_' + @TokenDate + '_' + @TokenTime + '.txt'

SET @JobName04 = 'DatabaseBackup - USER_DATABASES - LOG'
SET @JobCommand04 = 'sqlcmd -E -S ' + @TokenServer + ' -d ' + @Database + ' -Q "EXECUTE [dbo].[DatabaseBackup] @Databases = ''USER_DATABASES'', @Directory = ' + ISNULL('N''' + REPLACE(@BackupDirectory,'''','''''') + '''','NULL') + ', @BackupType = ''LOG'', @Verify = ''Y'', @CleanupTime = 120, @CheckSum = ''Y''" -b'
SET @OutputFile04 = @LogDirectory + '\DatabaseBackup_' + @TokenJobID + '_' + @TokenStepID + '_' + @TokenDate + '_' + @TokenTime + '.txt'

SET @JobName05 = 'DatabaseIntegrityCheck - SYSTEM_DATABASES'
SET @JobCommand05 = 'sqlcmd -E -S ' + @TokenServer + ' -d ' + @Database + ' -Q "EXECUTE [dbo].[DatabaseIntegrityCheck] @Databases = ''SYSTEM_DATABASES''" -b'
SET @OutputFile05 = @LogDirectory + '\DatabaseIntegrityCheck_' + @TokenJobID + '_' + @TokenStepID + '_' + @TokenDate + '_' + @TokenTime + '.txt'

SET @JobName06 = 'DatabaseIntegrityCheck - USER_DATABASES'
SET @JobCommand06 = 'sqlcmd -E -S ' + @TokenServer + ' -d ' + @Database + ' -Q "EXECUTE [dbo].[DatabaseIntegrityCheck] @Databases = ''USER_DATABASES''" -b'
SET @OutputFile06 = @LogDirectory + '\DatabaseIntegrityCheck_' + @TokenJobID + '_' + @TokenStepID + '_' + @TokenDate + '_' + @TokenTime + '.txt'

SET @JobName07 = 'IndexOptimize - USER_DATABASES'
--//  VersionOne V1 Paul S. Changed 4/13/11  
--// SET @JobCommand07 = 'sqlcmd -E -S ' + @TokenServer + ' -d ' + @Database + ' -Q "EXECUTE [dbo].[IndexOptimize] @Databases = ''USER_DATABASES''" -b'
SET @JobCommand07 = 'sqlcmd -E -S ' + @TokenServer + ' -d ' + @Database + ' -Q "EXECUTE [dbo].[IndexOptimize] @Databases = ''USER_DATABASES'', @FragmentationHigh = ''INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE'', @FragmentationMedium = ''INDEX_REORGANIZE'', @FragmentationLow = NULL, @PageCountLevel = 1000, @UpdateStatistics = ''ALL'', @OnlyModifiedStatistics = ''Y''" -b'
SET @OutputFile07 = @LogDirectory + '\IndexOptimize_' + @TokenJobID + '_' + @TokenStepID + '_' + @TokenDate + '_' + @TokenTime + '.txt'

SET @JobName08 = 'sp_delete_backuphistory'
SET @JobCommand08 = 'sqlcmd -E -S ' + @TokenServer + ' -d ' + 'msdb' + ' -Q "DECLARE @CleanupDate datetime SET @CleanupDate = DATEADD(dd,-30,GETDATE()) EXECUTE dbo.sp_delete_backuphistory @oldest_date = @CleanupDate" -b'
SET @OutputFile08 = @LogDirectory + '\sp_delete_backuphistory_' + @TokenJobID + '_' + @TokenStepID + '_' + @TokenDate + '_' + @TokenTime + '.txt'

SET @JobName09 = 'sp_purge_jobhistory'
SET @JobCommand09 = 'sqlcmd -E -S ' + @TokenServer + ' -d ' + 'msdb' + ' -Q "DECLARE @CleanupDate datetime SET @CleanupDate = DATEADD(dd,-30,GETDATE()) EXECUTE dbo.sp_purge_jobhistory @oldest_date = @CleanupDate" -b'
SET @OutputFile09 = @LogDirectory + '\sp_purge_jobhistory_' + @TokenJobID + '_' + @TokenStepID + '_' + @TokenDate + '_' + @TokenTime + '.txt'

SET @JobName10 = 'Output File Cleanup'
SET @JobCommand10 = 'cmd /q /c "For /F "tokens=1 delims=" %v In (''ForFiles /P "' + @LogDirectory + '" /m *_*_*_*_*.txt /d -30 2^>^&1'') do if not "%v" == "ERROR: No files found with the specified search criteria." echo del "' + @LogDirectory + '"\%v& del "' + @LogDirectory + '"\%v"'
SET @OutputFile10 = @LogDirectory + '\OutputFileCleanup_' + @TokenJobID + '_' + @TokenStepID + '_' + @TokenDate + '_' + @TokenTime + '.txt'

IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE [name] = @JobName01)
BEGIN
  EXECUTE msdb.dbo.sp_add_job @job_name = @JobName01
  EXECUTE msdb.dbo.sp_add_jobstep @job_name = @JobName01, @step_name = @JobName01, @subsystem = 'CMDEXEC', @command = @JobCommand01, @output_file_name = @OutputFile01
  EXECUTE msdb.dbo.sp_add_jobserver @job_name = @JobName01
END

IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE [name] = @JobName02)
BEGIN
  EXECUTE msdb.dbo.sp_add_job @job_name = @JobName02
  EXECUTE msdb.dbo.sp_add_jobstep @job_name = @JobName02, @step_name = @JobName02, @subsystem = 'CMDEXEC', @command = @JobCommand02, @output_file_name = @OutputFile02
  EXECUTE msdb.dbo.sp_add_jobserver @job_name = @JobName02
END

IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE [name] = @JobName03)
BEGIN
  EXECUTE msdb.dbo.sp_add_job @job_name = @JobName03
  EXECUTE msdb.dbo.sp_add_jobstep @job_name = @JobName03, @step_name = @JobName03, @subsystem = 'CMDEXEC', @command = @JobCommand03, @output_file_name = @OutputFile03
  EXECUTE msdb.dbo.sp_add_jobserver @job_name = @JobName03
END

IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE [name] = @JobName04)
BEGIN
  EXECUTE msdb.dbo.sp_add_job @job_name = @JobName04
  EXECUTE msdb.dbo.sp_add_jobstep @job_name = @JobName04, @step_name = @JobName04, @subsystem = 'CMDEXEC', @command = @JobCommand04, @output_file_name = @OutputFile04
  EXECUTE msdb.dbo.sp_add_jobserver @job_name = @JobName04
END

IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE [name] = @JobName05)
BEGIN
  EXECUTE msdb.dbo.sp_add_job @job_name = @JobName05
  EXECUTE msdb.dbo.sp_add_jobstep @job_name = @JobName05, @step_name = @JobName05, @subsystem = 'CMDEXEC', @command = @JobCommand05, @output_file_name = @OutputFile05
  EXECUTE msdb.dbo.sp_add_jobserver @job_name = @JobName05
END

IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE [name] = @JobName06)
BEGIN
  EXECUTE msdb.dbo.sp_add_job @job_name = @JobName06
  EXECUTE msdb.dbo.sp_add_jobstep @job_name = @JobName06, @step_name = @JobName06, @subsystem = 'CMDEXEC', @command = @JobCommand06, @output_file_name = @OutputFile06
  EXECUTE msdb.dbo.sp_add_jobserver @job_name = @JobName06
END

IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE [name] = @JobName07)
BEGIN
  EXECUTE msdb.dbo.sp_add_job @job_name = @JobName07
  EXECUTE msdb.dbo.sp_add_jobstep @job_name = @JobName07, @step_name = @JobName07, @subsystem = 'CMDEXEC', @command = @JobCommand07, @output_file_name = @OutputFile07
  EXECUTE msdb.dbo.sp_add_jobserver @job_name = @JobName07
END

IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE [name] = @JobName08)
BEGIN
  EXECUTE msdb.dbo.sp_add_job @job_name = @JobName08
  EXECUTE msdb.dbo.sp_add_jobstep @job_name = @JobName08, @step_name = @JobName08, @subsystem = 'CMDEXEC', @command = @JobCommand08, @output_file_name = @OutputFile08
  EXECUTE msdb.dbo.sp_add_jobserver @job_name = @JobName08
END

IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE [name] = @JobName09)
BEGIN
  EXECUTE msdb.dbo.sp_add_job @job_name = @JobName09
  EXECUTE msdb.dbo.sp_add_jobstep @job_name = @JobName09, @step_name = @JobName09, @subsystem = 'CMDEXEC', @command = @JobCommand09, @output_file_name = @OutputFile09
  EXECUTE msdb.dbo.sp_add_jobserver @job_name = @JobName09
END

IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE [name] = @JobName10)
BEGIN
  EXECUTE msdb.dbo.sp_add_job @job_name = @JobName10
  EXECUTE msdb.dbo.sp_add_jobstep @job_name = @JobName10, @step_name = @JobName10, @subsystem = 'CMDEXEC', @command = @JobCommand10, @output_file_name = @OutputFile10
  EXECUTE msdb.dbo.sp_add_jobserver @job_name = @JobName10
END
GO