
## This is instructions on how to execute new DBMaint (started using in Prod as of Spring'11)

1. Open MaintenanceSolution.sql and replace [master] only on the first line after comments with your database name
e.g. USE [master] => USE [V1Prod] (where V1Prod is your database instance name)

2. Execute MaintenanceSolution.sql as a stored procedure against your target DB.
It creates dbo.CommandExecute and dbo.IndexOptimize stored procedures required before proceeding to step #3.

3. Execute dbo.IndexOptimize stored procedure it will ask to supply several parameters. The only one you need
 to supply is the database name inside square brackets e.g. [V1ProdDB]
 You should now see a churning wheel and '0' as return value at the end of the execution.
 
 
If you have further questions see [Full Details from SQL SRvr consultant] (http://ola.hallengren.com/Documentation.html)
 
 