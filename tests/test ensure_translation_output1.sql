USE [dda_test]
GO

ALTER PROCEDURE [transformations].[test ensure_translation_output]
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
		19,
		'2021-01-28 15:37:41.667',
		N'dbo', 
		N'SortTable', 
		'sa', 
		'DELETE', 
		34827897, 
		1, 
		N'[{"key":[{"OrderID":30,"CustomerID":74}],"detail":[{"OrderID":30,"CustomerID":74,"OrderDate":"2020-10-20T13:48:39.567","Value":1873.62,"ColChar":"C7A3ED8B-AFE1-41BB-8ED9-F3777DA7D996                                                                                                                                                                                                                                                                                                                                                                                                                                                                                "}]}]' 
	), 
	(
		20,
		'2021-01-28 15:40:10.093',
		N'dbo', 
		N'SortTable', 
		'sa', 
		'INSERT', 
		34869927, 
		1, 
		N'[{"key":[{"OrderID":100027,"CustomerID":845}],"detail":[{"OrderID":100027,"CustomerID":845,"OrderDate":"2021-01-28T15:40:10.077","Value":99.60,"ColChar":"0xxxxx9945                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          "}]}]' 
	), 
	(
		1008,
		'2021-02-02 16:07:44.363',
		N'dbo', 
		N'SortTable', 
		'sa', 
		'UPDATE', 
		1812392, 
		3, 
		N'[{"key":[{"OrderID":249,"CustomerID":83}],"detail":[{"OrderDate":{"from":"2011-07-12T13:48:39.567","to":"2021-02-02T16:07:44.330"},"Value":{"from":1995.81,"to":33.99}}]},{"key":[{"OrderID":247,"CustomerID":178}],"detail":[{"OrderDate":{"from":"2016-04-14T13:48:39.567","to":"2021-02-02T16:07:44.330"},"Value":{"from":1886.08,"to":33.99}}]},{"key":[{"OrderID":246,"CustomerID":151}],"detail":[{"OrderDate":{"from":"2020-02-10T13:48:39.567","to":"2021-02-02T16:07:44.330"},"Value":{"from":1768.17,"to":33.99}}]}]' 
	);

	-- Create canned mappings: 
	EXEC [tSQLt].[FakeTable] @TableName = N'dda.translation_tables', @Identity = 1;
	INSERT INTO dda.[translation_tables] (
		[table_name],
		[translated_name]
	)
	VALUES	(
		N'dbo.SortTable',
		N'OrderHeader'
	);
	
	EXEC [tSQLt].[FakeTable] @TableName = N'dda.translation_columns', @Identity = 1;
	INSERT INTO dda.[translation_columns] (
		[table_name],
		[column_name],
		[translated_name]
	)
	VALUES	(
		N'dbo.SortTaBLe',
		N'ValUe', 
		N'OrderTotal'
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
		N'TRANSLATED:1000'
	),
	(
		N'dbo.SortTable',
		N'ColChar',
		N'xxx20FDCD2B-3321-48EA-81D6-094E658',
		N'Factorio'
	),
	(
		N'dbo.SortTable',
		N'Value',
		N'1995.81',
		N'FREE!!!'			-- this, currently, creates a bug/problem with the JSON (but having it HERE - in this test - is by design/on-purpose)
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
	DECLARE @auditId int = (SELECT audit_id FROM [#search_output] WHERE [row_number] = 3);
	DECLARE @tableName sysname = (SELECT [table] FROM [#search_output] WHERE [row_number] = 3);

	DECLARE @row1_json nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 1);
	DECLARE @row2_json nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 2);
	DECLARE @row3_json nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 3);
	
	EXEC [tSQLt].[AssertEquals] @Expected = 3, @Actual = @rowCount;
	EXEC [tSQLt].[AssertEquals] @Expected = 1008, @Actual = @auditId;
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'OrderHeader', @Actual = @tableName;

	DECLARE @message nvarchar(MAX) = N'Problem with JSON formatting - row 1';
	DECLARE @expectedJSON nvarchar(MAX) = N'[{"key":[{"OrderID":30,"CustomerID":74}],"detail":[{"OrderID":30,"CustomerID":74,"OrderDate":"2020-10-20T13:48:39.567","OrderTotal":1873.62,"ColChar":"C7A3ED8B-AFE1-41BB-8ED9-F3777DA7D996                                                                                            "}]}]';
	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row1_json, @Message = @message;

	SET @message = N'Problem with JSON formatting - row 2';
	SET @expectedJSON = N'[{"key":[{"OrderID":100027,"CustomerID":845}],"detail":[{"OrderID":100027,"CustomerID":845,"OrderDate":"2021-01-28T15:40:10.077","OrderTotal":99.60,"ColChar":"0xxxxx9945                                                                                                                      "}]}]';
	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row2_json, @Message = @message;

	SET @message = N'Problem with JSON formatting - row 3';
	SET @expectedJSON = N'[{"key": [{"OrderID":249,"CustomerID":83}],"detail":[{"OrderDate":{"from":"2011-07-12T13:48:39.567","to":"2021-02-02T16:07:44.330"},"OrderTotal":{"from":"FREE!!!","to":33.99}}]},{"key": [{"OrderID":247,"CustomerID":178}],"detail":[{"OrderDate":{"from":"2016-04-14T13:48:39.567","to":"2021-02-02T16:07:44.330"},"OrderTotal":{"from":1886.08,"to":33.99}}]},{"key": [{"OrderID":246,"CustomerID":151}],"detail":[{"OrderDate":{"from":"2020-02-10T13:48:39.567","to":"2021-02-02T16:07:44.330"},"OrderTotal":{"from":1768.17,"to":33.99}}]}]';
	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row3_json, @Message = @message;

END;
