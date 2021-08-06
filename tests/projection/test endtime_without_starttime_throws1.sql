
CREATE OR ALTER PROCEDURE [projection].[test endtime_without_starttime_throws]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	EXEC [tSQLt].[ExpectException]
		@ExpectedMessagePattern = N'%@StartTime MUST be specified if @EndTime is specified.%';	

	-----------------------------------------------------------------------------------------------------------------
	-- Act: 
	-----------------------------------------------------------------------------------------------------------------
	EXEC dda.[get_audit_data]
		@EndTime = '2020-12-18 20:14:15';

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------

END;