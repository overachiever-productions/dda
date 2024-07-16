
CREATE OR ALTER PROCEDURE [translation].[test translations_fail_to_preserve_numbers_as_strings]
AS
BEGIN
	/*
		NOTE: 
			This test is confirming expected behavior - namely that if we have a 'numeric' value stored/expressed as a string (e.g., "23")
				that if/when said value is mapped as a translation to, say, '999', it'll be treated (by default) as the raw-data-type that best
				makes sense - i.e., 999 is a number - not a string. Or, in other words, by DEFAULT, "23" translated to, say a translation value of '999' 
					will be rendered as 999 - not "999". 

				IF "23" should be translated as "999" then dda.translation_values should define a [target_json_type] of 1 - i.e.,  string to 'force' storage as a string.
	
				See [test translations_map_numbers_as_strings_when_directed] for more info... 
	*/


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
		8805,
		'2021-03-13 15:37:41.667',
		N'dbo', 
		N'BigInts', 
		'sa', 
		'INSERT', 
		34827897, 
		1, 
		N'[{"key":[{"bigid":10060000}],"detail":[{"number_column":{"from":"23","to":"87"}}]}]' 
	);

	-- simple mapping:
	EXEC [tSQLt].[FakeTable]
		@TableName = N'dda.translation_values';

	INSERT INTO dda.[translation_values] (
		[table_name],
		[column_name],
		[key_value],
		[translation_value]
	)
	VALUES	(
		N'dbo.BigInts', -- table_name - sysname
		N'number_column', -- column_name - sysname
		N'23', -- key_value - sysname
		N'999' -- translation_value - sysname
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
		@TargetTables = N'BigInts',
		@TransformOutput = 1,
		@FromIndex = 1,
		@ToIndex = 10;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	 DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]);
	 EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;

	 DECLARE @row1_json nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 1);

	 DECLARE @expectedJSON nvarchar(MAX) = N'[{"key":[{"bigid":10060000}],"detail":[{"number_column":{"from":999,"to":"87"}}]}]';
	 EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row1_json;

END;
