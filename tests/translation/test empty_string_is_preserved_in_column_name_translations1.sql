
CREATE OR ALTER PROCEDURE [translation].[test empty_string_is_preserved_in_column_name_translations]
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
		889,
		'2021-03-15 14:11:01.840',
		N'dbo', 
		N'CUSTOMER', 
		'CORP\CorpBill', 
		'UPDATE', 
		204495, 
		1, 
		N'[{"key":[{"CustId":"_Test3fffrtyhrt"}],"detail":[{"TotalStep":{"from":14,"to":15},"S15":{"from":"","to":"FileManagement"}}]}]' 
	);
	
	-- column rename: 
	EXEC [tSQLt].[FakeTable] @TableName = N'dda.translation_columns', @Identity = 1;
	INSERT INTO dda.[translation_columns] (
		[table_name],
		[column_name],
		[translated_name]
	)
	VALUES	(
		N'dbo.CUSTOMER',
		N'TotalStep', 
		N'Total_number_of_steps_in_the_profile'
	), (
		N'dbo.CUSTOMER',
		N'S15', 
		N'Target_process_for_work_step_15'
	), (
		N'dbo.CUSTOMER',
		N'CustId', 
		N'Profile_ID_(may_be_in_EBCDIC_or_ASCII)'
	)

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
		@StartAuditID = 889,
		@TransformOutput = 1,
		@FromIndex = 1,
		@ToIndex = 10;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]);
	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;

	DECLARE @row1_json nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 1);

	DECLARE @expectedJSON nvarchar(MAX) = N'[{"key":[{"Profile_ID_(may_be_in_EBCDIC_or_ASCII)":"_Test3fffrtyhrt"}],"detail":[{"Total_number_of_steps_in_the_profile":{"from":14,"to":15},"Target_process_for_work_step_15":{"from":"","to":"FileManagement"}}]}]';
	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row1_json;
END;
