
CREATE OR ALTER PROCEDURE [translation].[test value_translations_supersede_foreign_key_translations]
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
		1029,
		'2021-03-08 17:55:01.240',
		N'dbo', 
		N'login_metrics', 
		'sa', 
		'INSERT', 
		13465112, 
		1, 
		N'[{"key":[{"row_id":5450}],"detail":[{"row_id":5450,"entry_date":"2021-03-08T17:55:01.240","operation_type":"DL","batch_size":399,"login_creation_time_ms":999,"count_of_sys_principals":-999}]}]' 
	);

	EXEC [tSQLt].[FakeTable] @TableName = N'dbo.login_metric_operation_types', @Identity = 1;
	
	INSERT INTO [dbo].[login_metric_operation_types] (
		[operation_type],
		[operation_full_name]
	)
	VALUES	(
		N'DL', -- operation_type - sysname
		N'DELETE LOGIN' -- operation_full_name - sysname
	), (
		N'CL', 
		N'CREATE LOGIN'
	);

	-- Create FK mapping: 
	EXEC [tSQLt].[FakeTable] @TableName = N'dda.translation_keys', @Identity = 1;
	INSERT INTO dda.[translation_keys] (
		[table_name],
		[column_name],
		[key_table],
		[key_column],
		[value_column]
	)
	VALUES	(
		N'dbo.login_metrics', -- table_name - sysname
		N'operation_type', -- column_name - sysname
		N'dbo.login_metric_operation_types', -- key_table - sysname
		N'operation_type', -- key_column - sysname
		N'operation_full_name' -- value_column - sysname
	);

	-- NOTE: HAVE to fake these tables given that there are LEFT OUTER JOINs against them (that can remove/overwrite values if NULLs are found):
	EXEC [tSQLt].[FakeTable] @TableName = N'dda.translation_columns', @Identity = 1;
	EXEC [tSQLt].[FakeTable] @TableName = N'dda.translation_tables', @Identity = 1;

	-- now create a value that'll OVERWRITE "DELETE LOGIN":
	EXEC [tSQLt].[FakeTable] @TableName = N'dda.translation_values', @Identity = 1;

	INSERT INTO dda.[translation_values] (
		[table_name],
		[column_name],
		[key_value],
		[translation_value]
	)
	VALUES	(
		N'dbo.login_metrics', -- table_name - sysname
		N'operation_type', -- column_name - sysname
		N'DL', -- key_value - sysname
		N'Donkey Legion' -- translation_value - sysname
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
		@TargetTables = N'login_metrics',
		@TransformOutput = 1;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	DECLARE @row1_json nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 1);

	DECLARE @expectedJSON nvarchar(MAX) = N'[{"key":[{"row_id":5450}],"detail":[{"row_id":5450,"entry_date":"2021-03-08T17:55:01.240","operation_type":"Donkey Legion","batch_size":399,"login_creation_time_ms":999,"count_of_sys_principals":-999}]}]';
	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row1_json;

END;
