/*
	This test addresses "to": and "from": values within UPDATEs.

*/

CREATE OR ALTER PROCEDURE [projection].[test json_encoded_update_data_is_re-encoded]
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
		[original_login],
		[operation],
		[transaction_id],
		[row_count],
		[audit]
	)
	VALUES	(
		128,
		'2021-03-12 14:43:09.250',
		N'dbo', 
		N'FilePaths', 
		'kateg', 
		'UPDATE', 
		55531407, 
		1, 
		N'[{"key":[{"FilePathId":2}],"detail":[{"FilePath":{"from":"D:\\Dropbox\\Repositories\\dda\\core","to":"D:\\Dropbox\\Repositories\\dda\\deployment"}}]}]'
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
		@StartAuditID = 128;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------

	DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]); 
	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;

	DECLARE @expectedJson nvarchar(MAX) = N'[{"key":[{"FilePathId":2}],"detail":[{"FilePath":{"from":"D:\\Dropbox\\Repositories\\dda\\core","to":"D:\\Dropbox\\Repositories\\dda\\deployment"}}]}]';

	DECLARE @originaJson nvarchar(MAX) = (SELECT [audit] FROM dda.[audits] WHERE [audit_id] = 128);
	DECLARE @transformedJson nvarchar(MAX) = (SELECT [change_details] FROM [#search_output] WHERE [row_number] = 1);

	-- verify that if/when there are no translations, that we get 'out' what we put in - i.e., re-encoded JSON: 
	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJson, @Actual = @originaJson;
	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJson, @Actual = @transformedJson;

END;