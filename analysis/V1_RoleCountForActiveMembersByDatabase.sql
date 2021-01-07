CREATE TABLE #RoleByDatabase (
	[DatabaseName] VARCHAR(50),
	[RoleId] INT,
	[RoleName] VARCHAR(50),
	[ActiveMemberCount] INT,
	[ActiveMemberCount90Day] INT,
	[ActiveMemberCount30Day] INT,
);

DECLARE @Loop int
DECLARE @MaxLoop int
DECLARE @DBName varchar(300)
DECLARE @SQL varchar(max)

SET @Loop = 1
SET @DBName = ''
set nocount on
SET @MaxLoop =  (select count([name]) FROM sys.databases)

Declare myCursor CURSOR for select name from SYS.databases
open myCursor
fetch next from myCursor into @DBName
WHILE (@@FETCH_STATUS <> -1)
	BEGIN
			PRINT @DBName
			SET @SQL = 'USE ['+@DBName+'];
			IF (EXISTS (SELECT * 
				FROM INFORMATION_SCHEMA.TABLES 
                WHERE TABLE_NAME = ''Role_Now''))
			BEGIN
			INSERT INTO #RoleByDatabase
			SELECT * FROM (
			SELECT '''+@DBName+''' AS ''DatabaseName'', A.RoleId, A.RoleName, A.ActiveMemberCount , C.ActiveMemberCount90Day , B.ActiveMemberCount30Day
			FROM
			(
			SELECT [Role_Now].ID AS ''RoleId'', [String].[Value] AS ''RoleName'', COUNT(DISTINCT JoinTable.MemberID) AS ''ActiveMemberCount'', NULL AS ''ActiveMemberCount30Day'', NULL AS ''ActiveMemberCount90Day''
			FROM [Role_Now] 
				INNER JOIN [String] ON [Role_Now].[Name]=[String].[ID]
				LEFT JOIN (
					SELECT MemberID, RoleID FROM [ScopeMemberACL] INNER JOIN [Login] ON [ScopeMemberACL].MemberID = [Login].ID WHERE [Login].[IsLoginDisabled] = 0
					UNION
					SELECT MemberID, RoleID FROM [EffectiveACL] INNER JOIN [Login] ON [EffectiveACL].MemberID = [Login].ID WHERE [Login].[IsLoginDisabled] = 0
				) AS JoinTable ON JoinTable.RoleID = [Role_Now].ID 
			GROUP BY [Role_Now].ID, [String].[Value]
			) A INNER JOIN (
			SELECT [Role_Now].ID AS ''RoleId'', [String].[Value] AS ''RoleName'', NULL AS ''ActiveMemberCount'', COUNT(DISTINCT JoinTable.MemberID) AS ''ActiveMemberCount30Day'', NULL AS ''ActiveMemberCount90Day''
			FROM [Role_Now] 
				INNER JOIN [String] ON [Role_Now].[Name]=[String].[ID]
				LEFT JOIN (
					SELECT MemberID, RoleID 
					FROM 
						[ScopeMemberACL] 
						INNER JOIN [Login] ON [ScopeMemberACL].MemberID = [Login].ID 
						INNER JOIN [Access_Now] ON [ScopeMemberACL].MemberID = [Access_Now].ByID
					WHERE [Login].[IsLoginDisabled] = 0 AND [Access_Now].AccessedAt >= DATEADD(DAY, -30, GETDATE())
					UNION
					SELECT MemberID, RoleID 
					FROM [EffectiveACL] 
					INNER JOIN [Login] ON [EffectiveACL].MemberID = [Login].ID 
					INNER JOIN [Access_Now] ON [EffectiveACL].MemberID = [Access_Now].ByID
					WHERE [Login].[IsLoginDisabled] = 0 AND [Access_Now].AccessedAt >= DATEADD(DAY, -30, GETDATE())
				) AS JoinTable ON JoinTable.RoleID = [Role_Now].ID 
			GROUP BY [Role_Now].ID, [String].[Value]
			) B ON A.RoleId = B.RoleId
			INNER JOIN (
			SELECT [Role_Now].ID AS ''RoleId'', [String].[Value] AS ''RoleName'', NULL AS ''ActiveMemberCount'', COUNT(DISTINCT JoinTable.MemberID) AS ''ActiveMemberCount30Day'', COUNT(DISTINCT JoinTable.MemberID) AS ''ActiveMemberCount90Day''
			FROM [Role_Now] 
				INNER JOIN [String] ON [Role_Now].[Name]=[String].[ID]
				LEFT JOIN (
					SELECT MemberID, RoleID 
					FROM 
						[ScopeMemberACL] 
						INNER JOIN [Login] ON [ScopeMemberACL].MemberID = [Login].ID 
						INNER JOIN [Access_Now] ON [ScopeMemberACL].MemberID = [Access_Now].ByID
					WHERE [Login].[IsLoginDisabled] = 0 AND [Access_Now].AccessedAt >= DATEADD(DAY, -90, GETDATE())
					UNION
					SELECT MemberID, RoleID 
					FROM [EffectiveACL] 
					INNER JOIN [Login] ON [EffectiveACL].MemberID = [Login].ID 
					INNER JOIN [Access_Now] ON [EffectiveACL].MemberID = [Access_Now].ByID
					WHERE [Login].[IsLoginDisabled] = 0 AND [Access_Now].AccessedAt >= DATEADD(DAY, -90, GETDATE())
				) AS JoinTable ON JoinTable.RoleID = [Role_Now].ID 
			GROUP BY [Role_Now].ID, [String].[Value]
			) C ON A.RoleId = C.RoleId
			) D
			END';
		exec(@SQL);
		
		fetch next from myCursor into @DBName
	END
CLOSE myCursor
DEALLOCATE myCursor
SELECT * FROM #RoleByDatabase
DROP TABLE #RoleByDatabase