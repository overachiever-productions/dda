USE [dda_test]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [translation].[test column_name_translations_work_with_multi_row_captures]
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
		[user],
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
		2, 
		N'[{"key":[{"CalendarNumber":0,"Date":"2018-10-10T00:00:00"}],"detail":[{"Description":{"from":"xxddxfgb","to":"xxddxfgbs"}}]},{"key":[{"CalendarNumber":17,"Date":"2018-10-10T00:00:00"}],"detail":[{"Description2":{"from":"xxddxfgb2","to":"xxddxfgbs2"}}]}]' 
	);

	-- column translation: 
	EXEC [tSQLt].[FakeTable] @TableName = N'dda.translation_columns', @Identity = 1;
	INSERT INTO dda.[translation_columns] (
		[table_name],
		[column_name],
		[translated_name]
	)
	VALUES	(
		N'dbo.CalendarDates',
		N'CalendarNumber', 
		N'CalendarID'
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

	DECLARE @expectedJSON nvarchar(MAX) = N'[{"key":[{"CalendarID":0,"Date":"2018-10-10T00:00:00"}],"detail":[{"Description":{"from":"xxddxfgb","to":"xxddxfgbs"}}]},{"key":[{"CalendarID":17,"Date":"2018-10-10T00:00:00"}],"detail":[{"Description2":{"from":"xxddxfgb2","to":"xxddxfgbs2"}}]}]' ;
	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row1_json;
END;
