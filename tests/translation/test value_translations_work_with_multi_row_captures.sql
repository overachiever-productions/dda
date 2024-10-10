
CREATE OR ALTER PROCEDURE [translation].[test value_translations_work_with_multi_row_captures]
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
		[original_login],
		[operation],
		[transaction_id],
		[row_count],
		[audit]
	)
	VALUES	
	(
		8805,
		'2021-03-13 15:37:41.667',
		N'dbo', 
		N'BigInts', 
		'sa', 
		'INSERT', 
		34827897, 
		4, 
		N'[{"key":[{"bigid":10060000}],"detail":[{"some_data":{"from":"test","to":"test_7"}}]},{"key":[{"bigid":10060000}],"detail":[{"some_data":{"from":"test","to":"test_7"}}]},{"key":[{"bigid":10060000}],"detail":[{"some_data":{"from":"test","to":"test_7"}}]},{"key":[{"bigid":10060000}],"detail":[{"some_data":{"from":"test","to":"test_8"}}]}]' 
	);

	-- simple mapping:
	EXEC [tSQLt].[FakeTable]
		@TableName = N'dda.translation_values';

	INSERT INTO dda.[translation_values] (
		[table_name],
		[column_name],
		[key_value],
		[translation_value]
	)
	VALUES	(
		N'dbo.BigInts', -- table_name - sysname
		N'some_data', -- column_name - sysname
		N'test_7', -- key_value - sysname
		N'email-test' -- translation_value - sysname
	), 
	(
		N'dbo.BigInts', -- table_name - sysname
		N'some_data', -- column_name - sysname
		N'test_8', -- key_value - sysname
		N'sms-test' -- translation_value - sysname
	);

	DROP TABLE IF EXISTS #search_output;

	CREATE TABLE #search_output ( 
		[row_number] int NOT NULL,
		[total_rows] int NOT NULL, 
		[audit_id] int NOT NULL,
		[timestamp] datetime NOT NULL,
		[original_login] sysname NOT NULL,
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
		[original_login],
		[table],
		[transaction_id],
		[operation_type],
		[row_count],
		[change_details]
	)
	EXEC dda.[get_audit_data]
		@TargetTables = N'BigInts',
		@TransformOutput = 1,
		@FromIndex = 1,
		@ToIndex = 10;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	 DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]);
	 EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;

	 DECLARE @jsonRowCount int = (SELECT TOP 1 [row_count] FROM [#search_output]);
	 EXEC [tSQLt].[AssertEquals] @Expected = 4, @Actual = @jsonRowCount;

	 DECLARE @row1_json nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 1);

	 DECLARE @expectedJSON nvarchar(MAX) = N'[{"key":[{"bigid":10060000}],"detail":[{"some_data":{"from":"test","to":"email-test"}}]},{"key":[{"bigid":10060000}],"detail":[{"some_data":{"from":"test","to":"email-test"}}]},{"key":[{"bigid":10060000}],"detail":[{"some_data":{"from":"test","to":"email-test"}}]},{"key":[{"bigid":10060000}],"detail":[{"some_data":{"from":"test","to":"sms-test"}}]}]'; 
	 EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row1_json;

END;
