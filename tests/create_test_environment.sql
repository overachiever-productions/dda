/*
	Work in Progress
		Currently just a list of steps - along with SOME scripts. 
		Eventually this'll be a BUIILD script in its own right... 


*/

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 0. Create the Database if it doesn't exist, etc. 
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- 
IF NOT EXISTS (SELECT DB_ID('dda_test')) BEGIN 
	CREATE DATABASE dda_test;
END;
GO

-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 1. Deploy tSQLt... 
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- 
-- TODO: implement steps for deploying tSQLt... 



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