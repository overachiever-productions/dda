USE [dda_test]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [transformations].[test ensure_null_update_translations]
AS
BEGIN
	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	EXEC [tSQLt].[FakeTable] 
		@TableName = N'audits', 
		@SchemaName = N'dda';
	
	INSERT INTO dda.[audits] (
		[audit_id],
		[timestamp],
		[schema],
		[table],
		[user],
		[operation],
		[transaction_id],
		[row_count],
		[audit]
	)
	VALUES	
	(
		1029,
		'2021-01-28 15:37:41.667',
		N'dbo', 
		N'SortTable', 
		'sa', 
		'DELETE', 
		34827897, 
		1, 
		N'[{"key":[{"OrderID":101035,"CustomerID":450}],"detail":[{"ColChar":{"from":null,"to":"0x999                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               "}}]}]' 
	);

	-- Create canned mappings: 
	EXEC [tSQLt].[FakeTable] @TableName = N'dda.translation_values', @Identity = 1;
	INSERT INTO dda.[translation_values] (
		[table_name],
		[column_name],
		[key_value],
		[translation_value]
	)
	VALUES	
	(
		N'dbo.SortTablE',
		N'ColCHaR',
		N'0x999',
		N'TRANSLATED:1000'
	);

	DROP TABLE IF EXISTS #search_output;

	CREATE TABLE #search_output ( 
		[row_number] int NOT NULL,
		[total_rows] int NOT NULL, 
		[audit_id] int NOT NULL,
		[timestamp] datetime NOT NULL,
		[user] sysname NOT NULL,
		[transaction_id] sysname NOT NULL,
		[table] sysname NOT NULL,
		[operation_type] char(9) NOT NULL,
		[row_count] int NOT NULL,
		[change_details] nvarchar(max) NULL, 
	);
	   
	-----------------------------------------------------------------------------------------------------------------
	-- Act: 
	-----------------------------------------------------------------------------------------------------------------

	INSERT INTO [#search_output] (
		[row_number],
		[total_rows],
		[audit_id],
		[timestamp],
		[user],
		[table],
		[transaction_id],
		[operation_type],
		[row_count],
		[change_details]
	)
	EXEC dda.[get_audit_data]
		@TargetUsers = N'sa',
		@TransformOutput = 1,
		@FromIndex = 1,
		@ToIndex = 10;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------

	DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]);
	DECLARE @auditId int = (SELECT audit_id FROM [#search_output] WHERE [row_number] = 1);

	DECLARE @row1_json nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 1);

	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;
	EXEC [tSQLt].[AssertEquals] @Expected = 1029, @Actual = @auditId; 

	DECLARE @expectedJSON nvarchar(MAX) = N'[{"key":[{"OrderID":101035,"CustomerID":450}],"detail":[{"ColChar":{"from":null,"to":"TRANSLATED:1000"}}]}]';

	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row1_json;

END;
