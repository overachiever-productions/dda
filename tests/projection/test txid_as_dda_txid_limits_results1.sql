
CREATE OR ALTER PROCEDURE [projection].[test txid_as_dda_txid_limits_results]
AS
BEGIN

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
		@StartTransactionID = N'2021-071-55531407';

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------

	DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]); 

	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;	 
END;
