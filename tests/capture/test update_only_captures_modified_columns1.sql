
CREATE OR ALTER PROCEDURE [capture].[test update_only_captures_modified_columns]
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

	UPDATE dbo.[SortTable] 
	SET 
		[Value] = 999.99
	WHERE 
		[OrderID] IN (1, 2); 

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	
	DECLARE @rowCount int = (SELECT [row_count] FROM dda.[audits] WHERE [audit_id] = 2);
	EXEC [tSQLt].[AssertEquals] @Expected = 2, @Actual = @rowCount;

	DECLARE @operation sysname = (SELECT [operation] FROM dda.[audits] WHERE [audit_id] = 2);
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'UPDATE', @Actual = @operation;

	DECLARE @json nvarchar(MAX) = (SELECT [audit] FROM dda.[audits] WHERE [audit_id] = 2);

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

	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @count;

	DECLARE @value sysname; 
	SELECT @value = [key] FROM [#columns] WHERE [key] = N'Value';

	EXEC [tSQLt].[AssertEqualsString] @Expected = N'Value', @Actual = @value;

END;
