
CREATE OR ALTER PROCEDURE [capture].[test delete_captures_multi_row_deletes]
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

	DECLARE @rowCount int = (SELECT [row_count] FROM dda.[audits] WHERE [audit_id] = 2);
	EXEC [tSQLt].[AssertEquals] @Expected = 3, @Actual = @rowCount;

	DECLARE @operation sysname = (SELECT [operation] FROM dda.[audits] WHERE [audit_id] = 2);
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'DELETE', @Actual = @operation;

	DECLARE @json nvarchar(MAX) = NULLIF((SELECT [audit] FROM dda.[audits] WHERE [audit_id] = 2), N'');
	DECLARE @count int;

	WITH [rows] as (
		SELECT * FROM OPENJSON(@json, N'$')
	) 

	SELECT @count = COUNT(*) FROM [rows]; 

	EXEC [tSQLt].[AssertEquals] @Expected = 3, @Actual = @count;

END;
