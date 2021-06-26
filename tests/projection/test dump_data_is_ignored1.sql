
CREATE OR ALTER PROCEDURE [projection].[test dump_data_is_ignored]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	-- create canned audit records:
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
		9919,
		'2021-01-28 15:37:41.667',
		N'dbo', 
		N'Errors', 
		'bilbo', 
		'MUTATE',   -- not yet implemented but ... shouldn't cause problems with this test. 
		34827897, 
		1, 
		N'[{"key":[{}],"detail":[{}],"dump":[{"deleted":[{"ErrorID":32,"Severity":"122","ErrorMessage":"Test Error Here"},{"ErrorID":31,"Severity":"122","ErrorMessage":"Test Error Here"},{"ErrorID":30,"Severity":"122","ErrorMessage":"Test Error Here"}],"inserted":[{"ErrorID":132,"Severity":"122","ErrorMessage":"Test Error Here"},{"ErrorID":131,"Severity":"122","ErrorMessage":"Test Error Here"},{"ErrorID":130,"Severity":"122","ErrorMessage":"Test Error Here"}]}]}]' 
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
		@TargetUsers = N'bilbo',
		@TransformOutput = 1,
		@FromIndex = 1,
		@ToIndex = 10;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]);
	DECLARE @auditId int = (SELECT audit_id FROM [#search_output] WHERE [row_number] = 1);
	DECLARE @tableName sysname = (SELECT [table] FROM [#search_output] WHERE [row_number] = 1);

	DECLARE @row1_json nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 1);
	
	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;
	EXEC [tSQLt].[AssertEquals] @Expected = 9919, @Actual = @auditId;

	DECLARE @message nvarchar(MAX) = N'Problem with JSON formatting - row 1';
	DECLARE @expectedJSON nvarchar(MAX) = N'[{"key":[{}],"detail":[{}],"dump":[{"deleted":[{"ErrorID":32,"Severity":"122","ErrorMessage":"Test Error Here"},{"ErrorID":31,"Severity":"122","ErrorMessage":"Test Error Here"},{"ErrorID":30,"Severity":"122","ErrorMessage":"Test Error Here"}],"inserted":[{"ErrorID":132,"Severity":"122","ErrorMessage":"Test Error Here"},{"ErrorID":131,"Severity":"122","ErrorMessage":"Test Error Here"},{"ErrorID":130,"Severity":"122","ErrorMessage":"Test Error Here"}]}]}]'
	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row1_json, @Message = @message;
END;
