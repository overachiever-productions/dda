
CREATE OR ALTER PROCEDURE [json].[test int_as_string_is_string]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	DECLARE @dataType tinyint;

	-----------------------------------------------------------------------------------------------------------------
	-- Act: 
	-----------------------------------------------------------------------------------------------------------------
	SELECT @dataType = dda.[get_json_data_type]('''325''');

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @dataType;
	
END;
