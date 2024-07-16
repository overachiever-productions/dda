
CREATE OR ALTER PROCEDURE [projection].[test transformoutput_to_true_skips_dumps]
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
		[original_login],
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
		@TargetLogins = N'bilbo',
		@TransformOutput = 0,
		@StartAuditID = 9919;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------

	DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]); 
	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;

	DECLARE @row1_json nvarchar(MAX) = (SELECT change_details FROM [#search_output] WHERE [row_number] = 1);

	DECLARE @expectedJSON nvarchar(MAX) = N'[{"key":[{}],"detail":[{}],"dump":[{"deleted":[{"ErrorID":32,"Severity":"122","ErrorMessage":"Test Error Here"},{"ErrorID":31,"Severity":"122","ErrorMessage":"Test Error Here"},{"ErrorID":30,"Severity":"122","ErrorMessage":"Test Error Here"}],"inserted":[{"ErrorID":132,"Severity":"122","ErrorMessage":"Test Error Here"},{"ErrorID":131,"Severity":"122","ErrorMessage":"Test Error Here"},{"ErrorID":130,"Severity":"122","ErrorMessage":"Test Error Here"}]}]}]';
	EXEC [tSQLt].[AssertEqualsString] @Expected = @expectedJSON, @Actual = @row1_json;

END;