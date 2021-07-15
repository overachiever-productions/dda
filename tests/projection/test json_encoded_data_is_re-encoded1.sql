
CREATE OR ALTER PROCEDURE [projection].[test json_encoded_data_is_re-encoded]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	EXEC [tSQLt].[FakeTable] 
		@TableName = N'dda.audits', 
		@Identity = 1;
	
	EXEC [tSQLt].[FakeTable] 
		@TableName = N'dbo.FilePaths', 
		@Identity = 1;
	
	EXEC [tSQLt].[ApplyConstraint] 
		@TableName = N'dbo.FilePaths', 
		@ConstraintName = N'PK_FilePaths';

	EXEC [tSQLt].[ApplyTrigger] 
		@TableName = N'dbo.FilePaths', 
		@TriggerName = N'ddat_FilePaths';
	
	INSERT INTO dbo.[FilePaths] (
		[FilePath]
	)
	VALUES	(
		N'D:\Dropbox\Repositories\dda\core'
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
		[transaction_id],
		[table],
		[operation_type],
		[row_count],
		[change_details]
	)
	EXEC dda.[get_audit_data]
		@StartAuditID = 1;	

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]);
	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;

	DECLARE @expectedJson nvarchar(MAX) = N'[{"key":[{"FilePathId":1}],"detail":[{"FilePathId":1,"FilePath":"D:\\Dropbox\\Repositories\\dda\\core"}]}]';

	DECLARE @originaJson nvarchar(MAX) = (SELECT [audit] FROM dda.[audits] WHERE [audit_id] = 1);
	DECLARE @transformedJson nvarchar(MAX) = (SELECT [change_details] FROM [#search_output] WHERE [row_number] = 1);

	-- verify that if/when there are no translations, that we get 'out' what we put in - i.e., re-encoded JSON: 
	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJson, @Actual = @originaJson;
	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJson, @Actual = @transformedJson;

END;