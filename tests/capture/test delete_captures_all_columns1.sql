
CREATE OR ALTER PROCEDURE [capture].[test delete_captures_all_columns]
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
	WITH multiples AS ( 

		SELECT 
			27 [CustomerID], 
			GETDATE() [OrderDate], 
			999.33 [Value], 
			'xxxx_xxxx' [ColChar]

		UNION ALL  

		SELECT 
			28 [CustomerID], 
			GETDATE() [OrderDate], 
			1187.33 [Value], 
			'yyyy_yyyy' [ColChar]

		UNION ALL 
		
		SELECT 
			30 [CustomerID], 
			GETDATE() [OrderDate], 
			2258.33 [Value], 
			'zzzzz_zzzz' [ColChar]

		UNION ALL 
		
		SELECT 
			30 [CustomerID], 
			GETDATE() [OrderDate], 
			2268.33 [Value], 
			'aaaa_aaaa' [ColChar]
	)

	INSERT INTO [dbo].[SortTable] (
		[CustomerID],
		[OrderDate],
		[Value],
		[ColChar]
	)
	SELECT 
		[CustomerID],
		[OrderDate],
		[Value],
		[ColChar] 
	FROM 
		[multiples];	

	DELETE FROM dbo.[SortTable] WHERE [CustomerID] IN (28, 30);

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------

	DECLARE @operation sysname = (SELECT [operation] FROM dda.[audits] WHERE [audit_id] = 2);
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'DELETE', @Actual = @operation;

	DECLARE @json nvarchar(MAX) = NULLIF((SELECT [audit] FROM dda.[audits] WHERE [audit_id] = 2), N'');
	
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
