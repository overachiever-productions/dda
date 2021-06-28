
CREATE OR ALTER PROCEDURE [capture].[test capture_collects_transaction_id]
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

	DECLARE @txId int = (SELECT [transaction_id] FROM dda.[audits] WHERE [audit_id] = 1);

	EXEC [tSQLt].[AssertNotEquals] @Expected = NULL, @Actual = @txId;
	EXEC [tSQLt].[AssertLike] @ExpectedPattern = N'%[0-9]%', @Actual = @txId;
	
END;