
CREATE OR ALTER PROCEDURE [json].[test sql_null_is_json_null]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	DECLARE @dataType tinyint;

	-----------------------------------------------------------------------------------------------------------------
	-- Act: 
	-----------------------------------------------------------------------------------------------------------------
	SELECT @dataType = dda.[get_json_data_type](NULL);

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	EXEC [tSQLt].[AssertEquals] @Expected = 0, @Actual = @dataType;
	
END;
