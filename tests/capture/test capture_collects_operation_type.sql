
CREATE OR ALTER PROCEDURE [capture].[test capture_collects_operation_type]
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

	UPDATE dbo.[SortTable] 
	SET 
		[Value] = 88.75
	WHERE 
		[CustomerID] = 27;

	DELETE FROM dbo.[SortTable] WHERE [CustomerID] = 27;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------

	DECLARE @operation1 sysname, @operation2 sysname, @operation3 sysname; 

	SELECT @operation1 = [operation] FROM dda.[audits] WHERE [audit_id] = 1;
	SELECT @operation2 = [operation] FROM dda.[audits] WHERE [audit_id] = 2;
	SELECT @operation3 = [operation] FROM dda.[audits] WHERE [audit_id] = 3;

	EXEC [tSQLt].[AssertEqualsString] @Expected = N'INSERT', @Actual = @operation1;
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'UPDATE', @Actual = @operation2;
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'DELETE', @Actual = @operation3;

END;