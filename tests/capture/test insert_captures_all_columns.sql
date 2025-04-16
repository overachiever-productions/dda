
CREATE OR ALTER PROCEDURE [capture].[test insert_captures_all_columns]
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

	DECLARE @operation sysname = (SELECT [operation] FROM dda.[audits] WHERE [audit_id] = 1);
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'INSERT', @Actual = @operation;

	DECLARE @json nvarchar(MAX) = NULLIF((SELECT [audit] FROM dda.[audits] WHERE [audit_id] = 1), N'');
	
	WITH [result] AS ( 
		SELECT [value] FROM OPENJSON(JSON_QUERY(@json, N'$[0].detail'))
	) 

	SELECT 
		[x].[key]
	INTO 
		#columns
	FROM 
		[result] r
		CROSS APPLY OPENJSON(r.[value], N'$') x;

	DECLARE @count int = (SELECT COUNT(*) FROM [#columns] WHERE [key] IS NOT NULL);

	EXEC [tSQLt].[AssertEquals] @Expected = 5, @Actual = @count;

	DECLARE @orderId sysname, @customerId sysname, @orderDate sysname, @value sysname, @colChar sysname;

	SELECT @orderId = [key] FROM [#columns] WHERE [key] = N'OrderID';
	SELECT @customerId = [key] FROM [#columns] WHERE [key] = N'CustomerID';
	SELECT @orderDate = [key] FROM [#columns] WHERE [key] = N'OrderDate';
	SELECT @value = [key] FROM [#columns] WHERE [key] = N'Value';
	SELECT @colChar = [key] FROM [#columns] WHERE [key] = N'ColChar';

	EXEC [tSQLt].[AssertEqualsString] @Expected = N'OrderID', @Actual = @orderId;
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'CustomerID', @Actual = @customerId;
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'OrderDate', @Actual = @orderDate;
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'Value', @Actual = @value;
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'ColChar', @Actual = @colChar;
	
END;