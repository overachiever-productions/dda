
ALTER PROCEDURE [json].[test lowercase_truefalse_is_boolean]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	DECLARE @dataType1 tinyint;
	DECLARE @dataType2 tinyint;

	-----------------------------------------------------------------------------------------------------------------
	-- Act: 
	-----------------------------------------------------------------------------------------------------------------
	SELECT @dataType1 = dda.[get_json_data_type]('true');
	SELECT @dataType2 = dda.[get_json_data_type]('false');

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	EXEC [tSQLt].[AssertEquals] @Expected = 3, @Actual = @dataType1;
	EXEC [tSQLt].[AssertEquals] @Expected = 3, @Actual = @dataType2;

END;
