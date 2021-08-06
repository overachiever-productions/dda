
CREATE OR ALTER PROCEDURE [translation].[test translated_strings_are_json_encoded]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	EXEC [tSQLt].[FakeTable] 
		@TableName = N'dda.audits';
	
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
		88,
		'2021-03-12 10:43:09.250',
		N'dbo', 
		N'FilePaths', 
		'mikec', 
		'INSERT', 
		31407, 
		1, 
		N'[{"key":[{"FilePathId":1}],"detail":[{"FilePathId":1,"FilePath":"D:\\Dropbox\\Repositories\\dda\\core"}]}]'
	);

	EXEC [tSQLt].[FakeTable] 
		@TableName = N'dda.translation_values';

	INSERT INTO dda.[translation_values] (
		[table_name],
		[column_name],
		[key_value],
		[translation_value],
		[target_json_type]
	)
	VALUES	(
		N'dbo.FilePaths', -- table_name - sysname
		N'FilePath', -- column_name - sysname
		N'D:\Dropbox\Repositories\dda\core',
		N'D:\Repos\dda\core',
		1 -- target_json_type - tinyint
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
		@StartAuditID = 88,
		@TransformOutput = 1;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]);
	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;

	DECLARE @actualJson nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 1);
	DECLARE @expectedJson nvarchar(MAX) = N'[{"key":[{"FilePathId":1}],"detail":[{"FilePathId":1,"FilePath":"D:\\Repos\\dda\\core"}]}]';

	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJson, @Actual = @actualJson;

END;