
ALTER PROCEDURE [json].[test string_is_string]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	DECLARE @dataType tinyint;

	-----------------------------------------------------------------------------------------------------------------
	-- Act: 
	-----------------------------------------------------------------------------------------------------------------
	SELECT @dataType = dda.[get_json_data_type](N'this test is basically dumb...');

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @dataType;

END;
