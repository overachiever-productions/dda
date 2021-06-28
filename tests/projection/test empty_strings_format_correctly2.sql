
CREATE OR ALTER PROCEDURE [projection].[test empty_strings_format_correctly]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	-- create canned audit records:
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
		3901,
		'2021-03-13 15:37:41.667',
		N'dbo', 
		N'Customers', 
		'CORP\CorpBill', 
		'UPDATE', 
		34827897, 
		1, 
		N'[{"key":[{"CustId":"_Test3fffrtyhrt"}],"detail":[{"TotalStep":{"from":14,"to":15},"S15":{"from":"","to":"FileManagement"}}]}]' 
	);

	-- NO mappings. 

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
		@TargetUsers = N'CORP\CorpBill',
		@TransformOutput = 1,
		@FromIndex = 1,
		@ToIndex = 10;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	 DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]);
	 EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;

	 DECLARE @row1_json nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 1);

	 DECLARE @expectedJSON nvarchar(MAX) = N'[{"key":[{"CustId":"_Test3fffrtyhrt"}],"detail":[{"TotalStep":{"from":14,"to":15},"S15":{"from":"","to":"FileManagement"}}]}]';
	 EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row1_json;

END;