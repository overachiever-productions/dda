-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 1. Create various tables that can/will be used as mocks:
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- 
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
		CONSTRAINT [PK_GapsIslands] PRIMARY KEY CLUSTERED ([ID] ASC, [SeqNo] ASC)
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
GO



-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 2. Create test CLASSES
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- 

---- TODO: make these calls idempotent:
--EXEC [tSQLt].[NewTestClass] @ClassName = N'capture';
--EXEC [tSQLt].[NewTestClass] @ClassName = N'json';
--EXEC [tSQLt].[NewTestClass] @ClassName = N'projection';
--EXEC [tSQLt].[NewTestClass] @ClassName = N'translation';
--EXEC [tSQLt].[NewTestClass] @ClassName = N'utilities';
--GO
