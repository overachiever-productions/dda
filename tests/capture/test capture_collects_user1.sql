
CREATE OR ALTER PROCEDURE [capture].[test capture_collects_original_login]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	EXEC [tSQLt].[FakeTable] 
		@TableName = N'dda.audits', 
		@Identity = 1;
	
	EXEC [tSQLt].[FakeTable] 
		@TableName = N'dbo.SortTable', 
		@Identity = 1;

	EXEC [tSQLt].[ApplyTrigger] 
		@TableName = N'dbo.SortTable', 
		@TriggerName = N'ddat_SortTable';
	
	-----------------------------------------------------------------------------------------------------------------
	-- Act: 
	-----------------------------------------------------------------------------------------------------------------
	INSERT INTO [dbo].[SortTable] (
		[CustomerID],
		[OrderDate],
		[Value],
		[ColChar]
	)
	VALUES	(
		27,
		GETDATE(),
		2138.73,
		'52A0FD4B-B4EE-4A6C-A453-DBD67DE4E51C     '
	);

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	DECLARE @rowCount int = (SELECT COUNT(*) FROM dda.[audits]);
	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;

	DECLARE @user sysname = (SELECT [original_login] FROM dda.[audits] WHERE [audit_id] = 1); 
	DECLARE @currentUser sysname = ORIGINAL_LOGIN();
	EXEC [tSQLt].[AssertEqualsString] @Expected = @currentUser, @Actual = @user;
	 
END;