
CREATE OR ALTER PROCEDURE [translation].[test value_translations_are_case_insensitive]
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
		825,
		'2021-03-12 10:43:09.250',
		N'dbo', 
		N'CalendarDates', 
		'CORP\CorpBill', 
		'UPDATE', 
		31407, 
		1, 
		N'[{"key":[{"CalendarNumber":0,"Date":"2018-10-10T00:00:00"}],"detail":[{"Description":{"from":"xxddxfgb","to":"xxddxfgbs"}}]}]' 
	);

	-- table translation mapping: 
	EXEC [tSQLt].[FakeTable] @TableName = N'dda.translation_tables', @Identity = 1;
	INSERT INTO dda.[translation_tables] (
		[table_name],
		[translated_name]
	)
	VALUES	(
		N'dbo.calendarDATES',
		N'Pointer_to_the_CalendarNames_table'
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
		@StartAuditID = 825,
		@TransformOutput = 1,
		@FromIndex = 1,
		@ToIndex = 10;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	 DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]);
	 EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;

	 DECLARE @row1_json nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 1);

	 DECLARE @tableName sysname = (SELECT [table] FROM [#search_output] WHERE [row_number] = 1);
	 EXEC [tSQLt].[AssertEqualsString] @Expected = N'Pointer_to_the_CalendarNames_table', @Actual = @tableName;

	 DECLARE @expectedJSON nvarchar(MAX) = N'[{"key":[{"CalendarNumber":0,"Date":"2018-10-10T00:00:00"}],"detail":[{"Description":{"from":"xxddxfgb","to":"xxddxfgbs"}}]}]';
	 EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row1_json;
END;
