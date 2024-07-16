
CREATE OR ALTER PROCEDURE [projection].[test pagination_uses_defaults]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	EXEC [tSQLt].[FakeTable] 
		@TableName = N'dda.audits';

	DECLARE @loopId int = 0; 
	WHILE @loopId < 120 BEGIN 
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
			@loopId,
			'2021-03-12 10:43:09.250',
			N'dbo', 
			N'FilePaths', 
			'mikec', 
			'INSERT', 
			31407, 
			1, 
			N'[{"key":[{"FilePathId":1}],"detail":[{"FilePathId":1,"FilePath":"D:\\Dropbox\\Repositories\\dda\\core"}]}]'
		);

		SET @loopId += 1;
	END;

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
		@TargetTables = N'FilePaths';

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	DECLARE @totalAuditRows int = (SELECT COUNT(*) FROM dda.[audits]); 
	DECLARE @totalReturnedRows int = (SELECT COUNT(*) FROM [#search_output]);

	EXEC [tSQLt].[AssertEquals] @Expected = 120, @Actual = @totalAuditRows;
	EXEC [tSQLt].[AssertEquals] @Expected = 100, @Actual = @totalReturnedRows;

END;