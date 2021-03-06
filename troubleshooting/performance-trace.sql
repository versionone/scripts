
declare @file_Name nvarchar(255), @file_MaxMegabytes bigint
set @file_Name=''
set @file_MaxMegabytes = 50

declare @filter_SPID int, @filter_Database sysname, @filter_MinDuration bigint
set @filter_SPID=null
set @filter_Database=''
set @filter_MinDuration=0

declare @trace_QueryPlans bit, @trace_Starts bit, @trace_Statements bit, @trace_Locks bit, @trace_Warnings bit, @trace_Details bit, @trace_Cache bit
set @trace_QueryPlans = 1
set @trace_Starts = 1
set @trace_Statements = 1
set @trace_Locks = 1
set @trace_Warnings = 1
set @trace_Details = 1
set @trace_Cache = 1

if @file_Name='' begin
	raiserror('Assign a path and filename (but no extension) to @file_Name', 16, 0)
	goto finish
end


-- Create a Queue
declare @rc int
declare @TraceID int

exec @rc = sp_trace_create @TraceID output, 2, @file_Name, @file_MaxMegabytes, NULL 
if (@rc != 0) goto error

-- event IDs
declare @RPC_Completed int, @RPC_Starting int, @SQL_BatchCompleted int, @SQL_BatchStarting int, @AuditLogin int, @AuditLogout int, @Attention int, @ExistingConnection int, @AuditServerStartsandStops int, @DTCTransaction int, @AuditLoginFailed int, @EventLog int, @ErrorLog int, @Lock_Released int, @Lock_Acquired int, @Lock_Deadlock int, @Lock_Cancel int, @Lock_Timeout int, @DegreeofParallelism int, @Exception int, @SP_CacheMiss int, @SP_CacheInsert int, @SP_CacheRemove int, @SP_Recompile int, @SP_CacheHit int, @SQL_StmtStarting int, @SQL_StmtCompleted int, @SP_Starting int, @SP_Completed int, @SP_StmtStarting int, @SP_StmtCompleted int, @Object_Created int, @Object_Deleted int, @SQL_Transaction int, @Scan_Started int, @Scan_Stopped int, @CursorOpen int, @TransactionLog int, @HashWarning int, @AutoStats int, @Lock_DeadlockChain int, @Lock_Escalation int, @OLEDBErrors int, @ExecutionWarnings int, @ShowplanTextUnencoded int, @SortWarnings int, @CursorPrepare int, @PrepareSQL int, @ExecPreparedSQL int, @UnprepareSQL int, @CursorExecute int, @CursorRecompile int, @CursorImplicitConversion int, @CursorUnprepare int, @CursorClose int, @MissingColumnStatistics int, @MissingJoinPredicate int, @ServerMemoryChange int, @UserConfigurable0 int, @UserConfigurable1 int, @UserConfigurable2 int, @UserConfigurable3 int, @UserConfigurable4 int, @UserConfigurable5 int, @UserConfigurable6 int, @UserConfigurable7 int, @UserConfigurable8 int, @UserConfigurable9 int, @DataFileAutoGrow int, @LogFileAutoGrow int, @DataFileAutoShrink int, @LogFileAutoShrink int, @ShowplanText int, @ShowplanAll int, @ShowplanStatisticsProfile int, @RPC_OutputParameter int, @AuditStatementGDR int, @AuditObjectGDR int, @AuditAddLogin int, @AuditLoginGDR int, @AuditLoginChangeProperty int, @AuditLoginChangePassword int, @AuditAddLogintoServerRole int, @AuditAddDBUser int, @AuditAddMembertoDBRole int, @AuditAddRole int, @AuditAppRoleChangePassword int, @AuditStatementPermission int, @AuditSchemaObjectAccess int, @AuditBackupRestore int, @AuditDBCC int, @AuditChangeAudit int, @AuditObjectDerivedPermission int, @OLEDBCall int, @OLEDBQueryInterface int, @OLEDBDataRead int, @ShowplanXML int, @SQL_FullTextQuery int, @Broker_Conversation int, @DeprecationAnnouncement int, @DeprecationFinalSupport int, @ExchangeSpill int, @AuditDatabaseManagement int, @AuditDatabaseObjectManagement int, @AuditDatabasePrincipalManagement int, @AuditSchemaObjectManagement int, @AuditServerPrincipalImpersonation int, @AuditDatabasePrincipalImpersonation int, @AuditServerObjectTakeOwnership int, @AuditDatabaseObjectTakeOwnership int, @Broker_ConversationGroup int, @BlockedProcessReport int, @Broker_Connection int, @Broker_ForwardedMessageSent int, @Broker_ForwardedMessageDropped int, @Broker_MessageClassify int, @Broker_Transmission int, @Broker_QueueDisabled int, @ShowplanXMLStatisticsProfile int, @DeadlockGraph int, @Broker_RemoteMessageAcknowledgement int, @file_Close int, @AuditChangeDatabaseOwner int, @AuditSchemaObjectTakeOwnership int, @FT_CrawlStarted int, @FT_CrawlStopped int, @FT_CrawlAborted int, @AuditBrokerConversation int, @AuditBrokerLogin int, @Broker_MessageUndeliverable int, @Broker_CorruptedMessage int, @UserErrorMessage int, @Broker_Activation int, @Object_Altered int, @PerformanceStatistics int, @SQL_StmtRecompile int, @DatabaseMirroringStateChange int, @ShowplanXMLForQueryCompile int, @ShowplanAllForQueryCompile int, @AuditServerScopeGDR int, @AuditServerObjectGDR int, @AuditDatabaseObjectGDR int, @AuditServerOperation int, @AuditServerAlterTrace int, @AuditServerObjectManagement int, @AuditServerPrincipalManagement int, @AuditDatabaseOperation int, @AuditDatabaseObjectAccess int, @TM_BeginTranstarting int, @TM_BeginTrancompleted int, @TM_PromoteTranstarting int, @TM_PromoteTrancompleted int, @TM_CommitTranstarting int, @TM_CommitTrancompleted int, @TM_RollbackTranstarting int, @TM_RollbackTrancompleted int, @Lock_Timeout_gt0 int, @ProgressReport_OnlineIndexOperation int, @TM_SaveTranstarting int, @TM_SaveTrancompleted int, @BackgroundJobError int, @OLEDBProviderInformation int, @MountTape int, @AssemblyLoad int, @XQueryStaticType int, @QN_subscription int, @QN_parametertable int, @QN_template int, @QN_dynamics int
select @RPC_Completed=10, @RPC_Starting=11, @SQL_BatchCompleted=12, @SQL_BatchStarting=13, @AuditLogin=14, @AuditLogout=15, @Attention=16, @ExistingConnection=17, @AuditServerStartsandStops=18, @DTCTransaction=19, @AuditLoginFailed=20, @EventLog=21, @ErrorLog=22, @Lock_Released=23, @Lock_Acquired=24, @Lock_Deadlock=25, @Lock_Cancel=26, @Lock_Timeout=27, @DegreeofParallelism=28, @Exception=33, @SP_CacheMiss=34, @SP_CacheInsert=35, @SP_CacheRemove=36, @SP_Recompile=37, @SP_CacheHit=38, @SQL_StmtStarting=40, @SQL_StmtCompleted=41, @SP_Starting=42, @SP_Completed=43, @SP_StmtStarting=44, @SP_StmtCompleted=45, @Object_Created=46, @Object_Deleted=47, @SQL_Transaction=50, @Scan_Started=51, @Scan_Stopped=52, @CursorOpen=53, @TransactionLog=54, @HashWarning=55, @AutoStats=58, @Lock_DeadlockChain=59, @Lock_Escalation=60, @OLEDBErrors=61, @ExecutionWarnings=67, @ShowplanTextUnencoded=68, @SortWarnings=69, @CursorPrepare=70, @PrepareSQL=71, @ExecPreparedSQL=72, @UnprepareSQL=73, @CursorExecute=74, @CursorRecompile=75, @CursorImplicitConversion=76, @CursorUnprepare=77, @CursorClose=78, @MissingColumnStatistics=79, @MissingJoinPredicate=80, @ServerMemoryChange=81, @UserConfigurable0=82, @UserConfigurable1=83, @UserConfigurable2=84, @UserConfigurable3=85, @UserConfigurable4=86, @UserConfigurable5=87, @UserConfigurable6=88, @UserConfigurable7=89, @UserConfigurable8=90, @UserConfigurable9=91, @DataFileAutoGrow=92, @LogFileAutoGrow=93, @DataFileAutoShrink=94, @LogFileAutoShrink=95, @ShowplanText=96, @ShowplanAll=97, @ShowplanStatisticsProfile=98, @RPC_OutputParameter=100, @AuditStatementGDR=102, @AuditObjectGDR=103, @AuditAddLogin=104, @AuditLoginGDR=105, @AuditLoginChangeProperty=106, @AuditLoginChangePassword=107, @AuditAddLogintoServerRole=108, @AuditAddDBUser=109, @AuditAddMembertoDBRole=110, @AuditAddRole=111, @AuditAppRoleChangePassword=112, @AuditStatementPermission=113, @AuditSchemaObjectAccess=114, @AuditBackupRestore=115, @AuditDBCC=116, @AuditChangeAudit=117, @AuditObjectDerivedPermission=118, @OLEDBCall=119, @OLEDBQueryInterface=120, @OLEDBDataRead=121, @ShowplanXML=122, @SQL_FullTextQuery=123, @Broker_Conversation=124, @DeprecationAnnouncement=125, @DeprecationFinalSupport=126, @ExchangeSpill=127, @AuditDatabaseManagement=128, @AuditDatabaseObjectManagement=129, @AuditDatabasePrincipalManagement=130, @AuditSchemaObjectManagement=131, @AuditServerPrincipalImpersonation=132, @AuditDatabasePrincipalImpersonation=133, @AuditServerObjectTakeOwnership=134, @AuditDatabaseObjectTakeOwnership=135, @Broker_ConversationGroup=136, @BlockedProcessReport=137, @Broker_Connection=138, @Broker_ForwardedMessageSent=139, @Broker_ForwardedMessageDropped=140, @Broker_MessageClassify=141, @Broker_Transmission=142, @Broker_QueueDisabled=143, @ShowplanXMLStatisticsProfile=146, @DeadlockGraph=148, @Broker_RemoteMessageAcknowledgement=149, @file_Close=150, @AuditChangeDatabaseOwner=152, @AuditSchemaObjectTakeOwnership=153, @FT_CrawlStarted=155, @FT_CrawlStopped=156, @FT_CrawlAborted=157, @AuditBrokerConversation=158, @AuditBrokerLogin=159, @Broker_MessageUndeliverable=160, @Broker_CorruptedMessage=161, @UserErrorMessage=162, @Broker_Activation=163, @Object_Altered=164, @PerformanceStatistics=165, @SQL_StmtRecompile=166, @DatabaseMirroringStateChange=167, @ShowplanXMLForQueryCompile=168, @ShowplanAllForQueryCompile=169, @AuditServerScopeGDR=170, @AuditServerObjectGDR=171, @AuditDatabaseObjectGDR=172, @AuditServerOperation=173, @AuditServerAlterTrace=175, @AuditServerObjectManagement=176, @AuditServerPrincipalManagement=177, @AuditDatabaseOperation=178, @AuditDatabaseObjectAccess=180, @TM_BeginTranstarting=181, @TM_BeginTrancompleted=182, @TM_PromoteTranstarting=183, @TM_PromoteTrancompleted=184, @TM_CommitTranstarting=185, @TM_CommitTrancompleted=186, @TM_RollbackTranstarting=187, @TM_RollbackTrancompleted=188, @Lock_Timeout_gt0=189, @ProgressReport_OnlineIndexOperation=190, @TM_SaveTranstarting=191, @TM_SaveTrancompleted=192, @BackgroundJobError=193, @OLEDBProviderInformation=194, @MountTape=195, @AssemblyLoad=196, @XQueryStaticType=198, @QN_subscription=199, @QN_parametertable=200, @QN_template=201, @QN_dynamics=202

-- column IDs
declare @TextData int, @BinaryData int, @DatabaseID int, @TransactionID int, @LineNumber int, @NTUserName int, @NTDomainName int, @HostName int, @ClientProcessID int, @ApplicationName int, @LoginName int, @SPID int, @Duration int, @StartTime int, @EndTime int, @Reads int, @Writes int, @CPU int, @Permissions int, @Severity int, @EventSubClass int, @ObjectID int, @Success int, @IndexID int, @IntegerData int, @ServerName int, @EventClass int, @ObjectType int, @NestLevel int, @State int, @Error int, @Mode int, @Handle int, @ObjectName int, @DatabaseName int, @FileName int, @OwnerName int, @RoleName int, @TargetUserName int, @DBUserName int, @LoginSid int, @TargetLoginName int, @TargetLoginSid int, @ColumnPermissions int, @LinkedServerName int, @ProviderName int, @MethodName int, @RowCounts int, @RequestID int, @XactSequence int, @EventSequence int, @BigintData1 int, @BigintData2 int, @GUID int, @IntegerData2 int, @ObjectID2 int, @Type int, @OwnerID int, @ParentName int, @IsSystem int, @Offset int, @SourceDatabaseID int, @SqlHandle int, @SessionLoginName int
select @TextData=1, @BinaryData=2, @DatabaseID=3, @TransactionID=4, @LineNumber=5, @NTUserName=6, @NTDomainName=7, @HostName=8, @ClientProcessID=9, @ApplicationName=10, @LoginName=11, @SPID=12, @Duration=13, @StartTime=14, @EndTime=15, @Reads=16, @Writes=17, @CPU=18, @Permissions=19, @Severity=20, @EventSubClass=21, @ObjectID=22, @Success=23, @IndexID=24, @IntegerData=25, @ServerName=26, @EventClass=27, @ObjectType=28, @NestLevel=29, @State=30, @Error=31, @Mode=32, @Handle=33, @ObjectName=34, @DatabaseName=35, @FileName=36, @OwnerName=37, @RoleName=38, @TargetUserName=39, @DBUserName=40, @LoginSid=41, @TargetLoginName=42, @TargetLoginSid=43, @ColumnPermissions=44, @LinkedServerName=45, @ProviderName=46, @MethodName=47, @RowCounts=48, @RequestID=49, @XactSequence=50, @EventSequence=51, @BigintData1=52, @BigintData2=53, @GUID=54, @IntegerData2=55, @ObjectID2=56, @Type=57, @OwnerID=58, @ParentName=59, @IsSystem=60, @Offset=61, @SourceDatabaseID=62, @SqlHandle=63, @SessionLoginName=64

-- filter constants
declare @AND int, @OR int, @EQ int, @NEQ int, @GT int, @LT int, @GTE int, @LTE int, @LIKE int, @NOTLIKE int
select @AND=0, @OR=1, @EQ=0, @NEQ=1, @GT=2, @LT=3, @GTE=4, @LTE=5, @LIKE=6, @NOTLIKE=7


if (isnull(@filter_MinDuration,0) = 0 and (@trace_Starts = 1 or @trace_Statements = 1)) begin
	exec sp_trace_setevent @TraceID, @RPC_Starting, @SPID, 1
	exec sp_trace_setevent @TraceID, @RPC_Starting, @EventClass, 1
	exec sp_trace_setevent @TraceID, @RPC_Starting, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @RPC_Starting, @StartTime, 1
	exec sp_trace_setevent @TraceID, @RPC_Starting, @TextData, 1
	exec sp_trace_setevent @TraceID, @RPC_Starting, @BinaryData, 1
	exec sp_trace_setevent @TraceID, @RPC_Starting, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @RPC_Starting, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @RPC_Starting, @EventSequence, 1

	exec sp_trace_setevent @TraceID, @SQL_BatchStarting, @SPID, 1
	exec sp_trace_setevent @TraceID, @SQL_BatchStarting, @EventClass, 1
	exec sp_trace_setevent @TraceID, @SQL_BatchStarting, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @SQL_BatchStarting, @StartTime, 1
	exec sp_trace_setevent @TraceID, @SQL_BatchStarting, @TextData, 1
	exec sp_trace_setevent @TraceID, @SQL_BatchStarting, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @SQL_BatchStarting, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @SQL_BatchStarting, @EventSequence, 1
end

exec sp_trace_setevent @TraceID, @RPC_Completed, @SPID, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @EventClass, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @EventSubClass, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @StartTime, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @EndTime, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @Duration, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @CPU, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @Reads, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @Writes, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @TextData, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @BinaryData, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @Error, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @RowCounts, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @ApplicationName, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @DatabaseName, 1
exec sp_trace_setevent @TraceID, @RPC_Completed, @EventSequence, 1

exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @SPID, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @EventClass, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @EventSubClass, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @StartTime, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @EndTime, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @Duration, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @CPU, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @Reads, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @Writes, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @TextData, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @Error, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @RowCounts, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @ApplicationName, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @DatabaseName, 1
exec sp_trace_setevent @TraceID, @SQL_BatchCompleted, @EventSequence, 1

if (@trace_Statements=1) begin
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @SPID, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @EventClass, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @StartTime, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @EndTime, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @Duration, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @CPU, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @Reads, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @Writes, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @TextData, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @IntegerData, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @RowCounts, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtCompleted, @EventSequence, 1

	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @SPID, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @EventClass, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @StartTime, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @EndTime, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @Duration, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @CPU, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @Reads, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @Writes, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @TextData, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @ObjectID, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @ObjectName, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @ObjectType, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @IntegerData, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @RowCounts, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @SP_StmtCompleted, @EventSequence, 1
end

if (@trace_QueryPlans = 1) begin
	exec sp_trace_setevent @TraceID, @ShowplanXMLStatisticsProfile, @SPID, 1
	exec sp_trace_setevent @TraceID, @ShowplanXMLStatisticsProfile, @EventClass, 1
	exec sp_trace_setevent @TraceID, @ShowplanXMLStatisticsProfile, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @ShowplanXMLStatisticsProfile, @StartTime, 1
	exec sp_trace_setevent @TraceID, @ShowplanXMLStatisticsProfile, @TextData, 1
	exec sp_trace_setevent @TraceID, @ShowplanXMLStatisticsProfile, @BinaryData, 1
	exec sp_trace_setevent @TraceID, @ShowplanXMLStatisticsProfile, @IntegerData, 1
	exec sp_trace_setevent @TraceID, @ShowplanXMLStatisticsProfile, @ObjectID, 1
	exec sp_trace_setevent @TraceID, @ShowplanXMLStatisticsProfile, @ObjectName, 1
	exec sp_trace_setevent @TraceID, @ShowplanXMLStatisticsProfile, @ObjectType, 1
	exec sp_trace_setevent @TraceID, @ShowplanXMLStatisticsProfile, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @ShowplanXMLStatisticsProfile, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @ShowplanXMLStatisticsProfile, @EventSequence, 1
end

if (@trace_Warnings = 1) begin
	exec sp_trace_setevent @TraceID, @HashWarning, @SPID, 1
	exec sp_trace_setevent @TraceID, @HashWarning, @EventClass, 1
	exec sp_trace_setevent @TraceID, @HashWarning, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @HashWarning, @StartTime, 1
	exec sp_trace_setevent @TraceID, @HashWarning, @ObjectID, 1
	exec sp_trace_setevent @TraceID, @HashWarning, @IntegerData, 1
	exec sp_trace_setevent @TraceID, @HashWarning, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @HashWarning, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @HashWarning, @EventSequence, 1

	exec sp_trace_setevent @TraceID, @MissingJoinPredicate, @SPID, 1
	exec sp_trace_setevent @TraceID, @MissingJoinPredicate, @EventClass, 1
	exec sp_trace_setevent @TraceID, @MissingJoinPredicate, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @MissingJoinPredicate, @StartTime, 1
	exec sp_trace_setevent @TraceID, @MissingJoinPredicate, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @MissingJoinPredicate, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @MissingJoinPredicate, @EventSequence, 1

	exec sp_trace_setevent @TraceID, @SortWarnings, @SPID, 1
	exec sp_trace_setevent @TraceID, @SortWarnings, @EventClass, 1
	exec sp_trace_setevent @TraceID, @SortWarnings, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @SortWarnings, @StartTime, 1
	exec sp_trace_setevent @TraceID, @SortWarnings, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @SortWarnings, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @SortWarnings, @EventSequence, 1

	exec sp_trace_setevent @TraceID, @ExecutionWarnings, @SPID, 1
	exec sp_trace_setevent @TraceID, @ExecutionWarnings, @EventClass, 1
	exec sp_trace_setevent @TraceID, @ExecutionWarnings, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @ExecutionWarnings, @StartTime, 1
	exec sp_trace_setevent @TraceID, @ExecutionWarnings, @Duration, 1
	exec sp_trace_setevent @TraceID, @ExecutionWarnings, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @ExecutionWarnings, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @ExecutionWarnings, @EventSequence, 1

	exec sp_trace_setevent @TraceID, @SQL_FullTextQuery, @SPID, 1
	exec sp_trace_setevent @TraceID, @SQL_FullTextQuery, @EventClass, 1
	exec sp_trace_setevent @TraceID, @SQL_FullTextQuery, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @SQL_FullTextQuery, @StartTime, 1
	exec sp_trace_setevent @TraceID, @SQL_FullTextQuery, @EndTime, 1
	exec sp_trace_setevent @TraceID, @SQL_FullTextQuery, @Duration, 1
	exec sp_trace_setevent @TraceID, @SQL_FullTextQuery, @TextData, 1
	exec sp_trace_setevent @TraceID, @SQL_FullTextQuery, @Error, 1
	exec sp_trace_setevent @TraceID, @SQL_FullTextQuery, @IntegerData, 1
	exec sp_trace_setevent @TraceID, @SQL_FullTextQuery, @ObjectID, 1
	exec sp_trace_setevent @TraceID, @SQL_FullTextQuery, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @SQL_FullTextQuery, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @SQL_FullTextQuery, @EventSequence, 1

	exec sp_trace_setevent @TraceID, @SQL_StmtRecompile, @SPID, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtRecompile, @EventClass, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtRecompile, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtRecompile, @StartTime, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtRecompile, @TextData, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtRecompile, @ObjectID, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtRecompile, @ObjectName, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtRecompile, @ObjectType, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtRecompile, @SqlHandle, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtRecompile, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtRecompile, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @SQL_StmtRecompile, @EventSequence, 1
end

if (@trace_Locks = 1) begin
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @SPID, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @EventClass, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @StartTime, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @EndTime, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @Duration, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @TextData, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @BinaryData, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @IntegerData, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @Mode, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @ObjectID, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @ObjectID2, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @OwnerID, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @Type, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @Lock_Deadlock, @EventSequence, 1

	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @SPID, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @EventClass, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @StartTime, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @TextData, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @BinaryData, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @IntegerData, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @Mode, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @ObjectID, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @ObjectID2, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @OwnerID, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @Type, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @Lock_DeadlockChain, @EventSequence, 1

	exec sp_trace_setevent @TraceID, @DeadlockGraph, @SPID, 1
	exec sp_trace_setevent @TraceID, @DeadlockGraph, @EventClass, 1
	exec sp_trace_setevent @TraceID, @DeadlockGraph, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @DeadlockGraph, @StartTime, 1
	exec sp_trace_setevent @TraceID, @DeadlockGraph, @TextData, 1
	exec sp_trace_setevent @TraceID, @DeadlockGraph, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @DeadlockGraph, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @DeadlockGraph, @EventSequence, 1

	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @SPID, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @EventClass, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @StartTime, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @EndTime, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @Duration, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @TextData, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @BinaryData, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @Mode, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @ObjectID, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @ObjectID2, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @OwnerID, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @Type, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @Lock_Timeout_gt0, @EventSequence, 1
end

if (@trace_Details = 1) begin
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @SPID, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @EventClass, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @StartTime, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @Duration, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @CPU, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @TextData, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @IntegerData, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @IntegerData2, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @BigintData1, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @BigintData2, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @BinaryData, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @ObjectID, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @SqlHandle, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @Handle, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @PerformanceStatistics, @EventSequence, 1
end

if (@trace_Cache = 1) begin
	exec sp_trace_setevent @TraceID, @SP_CacheHit, @SPID, 1
	exec sp_trace_setevent @TraceID, @SP_CacheHit, @EventClass, 1
	exec sp_trace_setevent @TraceID, @SP_CacheHit, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @SP_CacheHit, @StartTime, 1
	exec sp_trace_setevent @TraceID, @SP_CacheHit, @TextData, 1
	exec sp_trace_setevent @TraceID, @SP_CacheHit, @ObjectID, 1
	exec sp_trace_setevent @TraceID, @SP_CacheHit, @ObjectName, 1
	exec sp_trace_setevent @TraceID, @SP_CacheHit, @ObjectType, 1
	exec sp_trace_setevent @TraceID, @SP_CacheHit, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @SP_CacheHit, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @SP_CacheHit, @EventSequence, 1

	exec sp_trace_setevent @TraceID, @SP_CacheMiss, @SPID, 1
	exec sp_trace_setevent @TraceID, @SP_CacheMiss, @EventClass, 1
	exec sp_trace_setevent @TraceID, @SP_CacheMiss, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @SP_CacheMiss, @StartTime, 1
	exec sp_trace_setevent @TraceID, @SP_CacheMiss, @TextData, 1
	exec sp_trace_setevent @TraceID, @SP_CacheMiss, @ObjectID, 1
	exec sp_trace_setevent @TraceID, @SP_CacheMiss, @ObjectName, 1
	exec sp_trace_setevent @TraceID, @SP_CacheMiss, @ObjectType, 1
	exec sp_trace_setevent @TraceID, @SP_CacheMiss, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @SP_CacheMiss, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @SP_CacheMiss, @EventSequence, 1

	exec sp_trace_setevent @TraceID, @SP_CacheInsert, @SPID, 1
	exec sp_trace_setevent @TraceID, @SP_CacheInsert, @EventClass, 1
	exec sp_trace_setevent @TraceID, @SP_CacheInsert, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @SP_CacheInsert, @StartTime, 1
	exec sp_trace_setevent @TraceID, @SP_CacheInsert, @TextData, 1
	exec sp_trace_setevent @TraceID, @SP_CacheInsert, @ObjectID, 1
	exec sp_trace_setevent @TraceID, @SP_CacheInsert, @ObjectName, 1
	exec sp_trace_setevent @TraceID, @SP_CacheInsert, @ObjectType, 1
	exec sp_trace_setevent @TraceID, @SP_CacheInsert, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @SP_CacheInsert, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @SP_CacheInsert, @EventSequence, 1

	exec sp_trace_setevent @TraceID, @SP_CacheRemove, @SPID, 1
	exec sp_trace_setevent @TraceID, @SP_CacheRemove, @EventClass, 1
	exec sp_trace_setevent @TraceID, @SP_CacheRemove, @EventSubClass, 1
	exec sp_trace_setevent @TraceID, @SP_CacheRemove, @StartTime, 1
	exec sp_trace_setevent @TraceID, @SP_CacheRemove, @TextData, 1
	exec sp_trace_setevent @TraceID, @SP_CacheRemove, @ObjectID, 1
	exec sp_trace_setevent @TraceID, @SP_CacheRemove, @ObjectName, 1
	exec sp_trace_setevent @TraceID, @SP_CacheRemove, @ObjectType, 1
	exec sp_trace_setevent @TraceID, @SP_CacheRemove, @ApplicationName, 1
	exec sp_trace_setevent @TraceID, @SP_CacheRemove, @DatabaseName, 1
	exec sp_trace_setevent @TraceID, @SP_CacheRemove, @EventSequence, 1
end

exec sp_trace_setevent @TraceID, @ErrorLog, @SPID, 1
exec sp_trace_setevent @TraceID, @ErrorLog, @EventClass, 1
exec sp_trace_setevent @TraceID, @ErrorLog, @EventSubClass, 1
exec sp_trace_setevent @TraceID, @ErrorLog, @StartTime, 1
exec sp_trace_setevent @TraceID, @ErrorLog, @TextData, 1
exec sp_trace_setevent @TraceID, @ErrorLog, @Error, 1
exec sp_trace_setevent @TraceID, @ErrorLog, @Severity, 1
exec sp_trace_setevent @TraceID, @ErrorLog, @ApplicationName, 1
exec sp_trace_setevent @TraceID, @ErrorLog, @DatabaseName, 1
exec sp_trace_setevent @TraceID, @ErrorLog, @EventSequence, 1

if @filter_Database<>'' begin
	-- DatabaseName like @filter_Database and DatabaseName is not null
	exec sp_trace_setfilter @TraceID, @DatabaseName, @AND, @LIKE, @filter_Database
	exec sp_trace_setfilter @TraceID, @DatabaseName, @AND, @NEQ, NULL
end

if @filter_MinDuration>0 begin
	-- Duration >= @filter_MinDuration
	declare @filter_MinDurationMicroseconds bigint; set @filter_MinDurationMicroseconds = @filter_MinDuration*1000
	exec sp_trace_setfilter @TraceID, @Duration, @AND, @GTE, @filter_MinDurationMicroseconds
end

-- Error<>5701 and Error<>8153
exec sp_trace_setfilter @TraceID, @Error, @AND, @NEQ, 5701
exec sp_trace_setfilter @TraceID, @Error, @AND, @NEQ, 8153

-- no sp_reset_connection statements
exec sp_trace_setfilter @TraceID, @TextData, @AND, @NEQ, N'exec sp_reset_connection'

-- not remaining statements from this script
if @filter_SPID is null begin
	declare @mySPID int; select @mySPID=@@SPID
	exec sp_trace_setfilter @TraceID, @SPID, @AND, @NEQ, @mySPID
end else begin
	exec sp_trace_setfilter @TraceID, @SPID, @AND, @EQ, @filter_SPID
	exec sp_trace_setfilter @TraceID, @SPID, @AND, @NEQ, NULL
end

-- Start the trace
exec sp_trace_setstatus @TraceID, 1
print 'Trace logging to ' + @file_Name
print 'To stop, execute: '
print 'exec sp_trace_setstatus ' + cast(@TraceID as varchar(10)) + ', 0; exec sp_trace_setstatus ' + cast(@TraceID as varchar(10)) + ', 2'

goto finish

error: 
select ErrorCode=@rc

finish: 
go
