/*
	Work in Progress
		Currently just a list of steps - along with SOME scripts. 
		Eventually this'll be a BUILD script in its own right... 



	TODO: 
		- this eventually needs to be a POWERSHELL script that'll: 
			- take in the name of a SQL Server (instance) + optional creds. 
			- take in the name of a TARGET database. 
				- allow a -Force or -Overwrite switch (to nuke/remove the previous). 
			- create the DB in question. 
			- then run dda_latest.sql
			- and... create the test tables I've got in this script
			- and ... create ALL of the tests (.sql files).

		CUZ... tSQLt - as awesome as it is, occassionally lets TRANSACTIONs leak... 

*/

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 0. Create the Database if it doesn't exist, etc. 
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- 
IF DB_ID('dda_test') IS NULL BEGIN 
	CREATE DATABASE dda_test;
END;
GO

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 1. Deploy tSQLt... 
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- 
-- TODO: implement steps for deploying tSQLt... 
-- best option to do this is via Redgate SQLTest - i.e., just use the GUI. 


-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 2. Deploy dda_latest.sql
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- 

-- TODO: ... run/execute dda_latest.sql here... 

USE [dda_test];
GO

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 3. Create various tables that can/will be used as mocks:
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- 

USE [dda_test];
GO

IF OBJECT_ID(N'dbo.login_metric_operation_types', N'U') IS NULL BEGIN
	CREATE TABLE [dbo].[login_metric_operation_types](
		[row_id] [int] IDENTITY(1,1) NOT NULL,
		[operation_type] [sysname] NOT NULL,
		[operation_full_name] [sysname] NOT NULL
	) ON [PRIMARY];

	EXEC dda.[enable_table_auditing] 
		@TargetTable = N'login_metric_operation_types', 
		@SurrogateKeys = N'row_id';

END;

IF OBJECT_ID(N'dbo.SortTable', N'U') IS NULL BEGIN
	CREATE TABLE [dbo].[SortTable](
		[OrderID] [int] IDENTITY(1,1) NOT NULL,
		[CustomerID] [int] NULL,
		[OrderDate] [datetime] NULL,
		[Value] [numeric](18, 2) NOT NULL,
		[ColChar] [char](500) NULL
	) ON [PRIMARY];

	EXEC dda.[enable_table_auditing] 
		@TargetTable = N'SortTable', 
		@SurrogateKeys = N'OrderID';
END;

IF OBJECT_ID(N'dbo.FilePaths', N'U') IS NULL BEGIN 
	CREATE TABLE dbo.FilePaths (
		FilePathId int IDENTITY(1,1) NOT NULL, 
		FilePath sysname NOT NULL, 
		CONSTRAINT PK_FilePaths PRIMARY KEY CLUSTERED ([FilePathId]) 
	); 

	EXEC dda.[enable_table_auditing]
		@TargetTable = N'FilePaths';

END;


IF OBJECT_ID(N'dbo.GapsIslands', N'U') IS NULL BEGIN
	CREATE TABLE [dbo].[GapsIslands](
		[ID] int NOT NULL,
		[SeqNo] int NOT NULL,
		CONSTRAINT [pk_GapsIslands] PRIMARY KEY CLUSTERED ([ID] ASC, [SeqNo] ASC)
	);

	EXEC dda.[enable_table_auditing]
		@TargetTable = N'GapsIslands';

END;

IF OBJECT_ID(N'dbo.KeyOnly', N'U') IS NULL BEGIN
	CREATE TABLE [dbo].[KeyOnly](
		[KeyNumber] [int] NOT NULL,
		CONSTRAINT [PK_KeyOnly] PRIMARY KEY CLUSTERED ([KeyNumber] ASC)
	);

	EXEC dda.[enable_table_auditing]
		@TargetTable = N'KeyOnly';
END;




-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 4. Create test CLASSES
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- 

-- TODO: make these calls idempotent:
EXEC [tSQLt].[NewTestClass] @ClassName = N'capture';
EXEC [tSQLt].[NewTestClass] @ClassName = N'json';
EXEC [tSQLt].[NewTestClass] @ClassName = N'projection';
EXEC [tSQLt].[NewTestClass] @ClassName = N'translation';
--EXEC [tSQLt].[NewTestClass] @ClassName = N'utilities';


-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 5. Import/create Tests
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- 

-- TODO: 
--  for each of the folders in the tests folder, open up and run/execute each .sql file (i.e., create each test).

/*

		Import-Module -Name "D:\Dropbox\Repositories\psi" -Force;
		$creds = New-Object PSCredential("sa", (ConvertTo-SecureString "Pass@word1" -AsPlainText -Force));
		$files = Get-ChildItem -Path "D:\Dropbox\Repositories\dda\tests\capture" -Filter "*.sql";
		Invoke-PsiCommand -SqlInstance "dev.sqlserver.id" -Database "dda_test" -File $files -SqlCredential $creds;

		$files = Get-ChildItem -Path "D:\Dropbox\Repositories\dda\tests\json" -Filter "*.sql";
		Invoke-PsiCommand -SqlInstance "dev.sqlserver.id" -Database "dda_test" -File $files -SqlCredential $creds;

		$files = Get-ChildItem -Path "D:\Dropbox\Repositories\dda\tests\projection" -Filter "*.sql";
		Invoke-PsiCommand -SqlInstance "dev.sqlserver.id" -Database "dda_test" -File $files -SqlCredential $creds;

		$files = Get-ChildItem -Path "D:\Dropbox\Repositories\dda\tests\translation" -Filter "*.sql";
		Invoke-PsiCommand -SqlInstance "dev.sqlserver.id" -Database "dda_test" -File $files -SqlCredential $creds;


		#$files = Get-ChildItem -Path "D:\Dropbox\Repositories\dda\tests\utilities" -Filter "*.sql";
		#Invoke-PsiCommand -SqlInstance "dev.sqlserver.id" -Database "dda_test" -File $files -SqlCredential $creds;

*/