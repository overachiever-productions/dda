
CREATE OR ALTER PROCEDURE [translation].[test json_data_is_not_xml_encoded]
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
		[original_login],
		[operation],
		[transaction_id],
		[row_count],
		[audit]
	)
	VALUES	
	(
		19,
		'2021-01-28 15:37:41.667',
		N'dbo', 
		N'SortTable', 
		'sa', 
		'DELETE', 
		34827897, 
		1, 
		N'[{"key":[{"OrderID":30,"CustomerID":74}],"detail":[{"OrderID":30,"CustomerID":74,"OrderDate":"2020-10-20T13:48:39.567","Value":1873.62,"ColChar":"0x999"}]}]' 
	);

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
		N'<EMPTY>' -- want/expect <EMTPY> not &lt;EMTPTY&gt;
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
		@TargetLogins = N'sa',
		@TransformOutput = 1,
		@StartAuditID = 19;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	DECLARE @row1_json nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 1);

	DECLARE @expectedJSON nvarchar(MAX) = N'[{"key":[{"OrderID":30,"CustomerID":74}],"detail":[{"OrderID":30,"CustomerID":74,"OrderDate":"2020-10-20T13:48:39.567","Value":1873.62,"ColChar":"<EMPTY>"}]}]';
	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row1_json;	 
END;
