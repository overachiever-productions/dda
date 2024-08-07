
CREATE OR ALTER PROCEDURE [projection].[test txid_as_number_only_with_txdate_limits_results]
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
	), 
	(
		98,
		'2021-03-12 11:43:09.250',
		N'dbo', 
		N'FilePaths', 
		'mikec', 
		'INSERT', 
		231407, 
		1, 
		N'[{"key":[{"FilePathId":2}],"detail":[{"FilePathId":2,"FilePath":"D:\\Dropbox\\Repositories\\S4\\Common"}]}]'
	), 
	(
		108,
		'2021-03-12 12:43:09.250',
		N'dbo', 
		N'FilePaths', 
		'toms', 
		'INSERT', 
		3331407, 
		1, 
		N'[{"key":[{"FilePathId":3}],"detail":[{"FilePathId":3,"FilePath":"D:\\Dropbox\\Repositories\\proviso\\workflows"}]}]'
	), 
	(
		118,
		'2021-03-12 13:43:09.250',
		N'dbo', 
		N'FilePaths', 
		'toms', 
		'INSERT', 
		4431407, 
		1, 
		N'[{"key":[{"FilePathId":4}],"detail":[{"FilePathId":4,"FilePath":"D:\\Dropbox\\Repositories\\tsmake\\tsmake.core"}]}]'
	), 
	(
		128,
		'2021-03-12 14:43:09.250',
		N'dbo', 
		N'FilePaths', 
		'kateg', 
		'INSERT', 
		55531407, 
		1, 
		N'[{"key":[{"FilePathId":5}],"detail":[{"FilePathId":5,"FilePath":"D:\\Dropbox\\Repositories\\SSA\\code"}]}]'
	), 
	(
		138,
		'2021-03-12 15:43:09.250',
		N'dbo', 
		N'FilePaths', 
		'kateg', 
		'INSERT', 
		66631407, 
		1, 
		N'[{"key":[{"FilePathId":6}],"detail":[{"FilePathId":6,"FilePath":"D:\\Dropbox\\Repositories\\Billing\\Design"}]}]'
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
		@StartTransactionID = 3331400, 
		@EndTransactionID = 55531900, 
		@TransactionDate = '2021-03-12';

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------

	DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]); 

	EXEC [tSQLt].[AssertEquals] @Expected = 3, @Actual = @rowCount;
END;
