
CREATE OR ALTER PROCEDURE [capture].[test update_vs_single_row_as_mutate_is_update]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	EXEC [tSQLt].[FakeTable] 
		@TableName = N'dda.audits', 
		@Identity = 1;
	
	EXEC [tSQLt].[FakeTable] 
		@TableName = N'dbo.GapsIslands', 
		@Identity = 1;

	EXEC [tSQLt].[ApplyConstraint]
		@TableName =  N'dbo.GapsIslands',
		@ConstraintName = 'PK_GapsIslands';

	EXEC [tSQLt].[ApplyTrigger] 
		@TableName = N'dbo.GapsIslands', 
		@TriggerName = N'ddat_GapsIslands';

	-----------------------------------------------------------------------------------------------------------------
	-- Act: 
	-----------------------------------------------------------------------------------------------------------------
	WITH multiples AS ( 

		SELECT 
			1 [ID], 
			18 [SeqNo]

		UNION ALL  

		SELECT 
			2 [ID], 
			48 [SeqNo]

		UNION ALL 
		
		SELECT 
			3 [ID], 
			124 [SeqNo]

		UNION ALL 
		
		SELECT 
			4 [ID], 
			189 [SeqNo]
	)

	INSERT INTO [dbo].[GapsIslands] (
		[ID],
		[SeqNo]
	)
	SELECT 
		[ID], 
		[SeqNo]
	FROM 
		[multiples];	

	UPDATE dbo.GapsIslands 
	SET 
		[SeqNo] = 87
	WHERE 
		[ID] = 2;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------

	DECLARE @rowCount int = (SELECT [row_count] FROM dda.[audits] WHERE [audit_id] = 2);
	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;

	DECLARE @operation sysname = (SELECT [operation] FROM dda.[audits] WHERE [audit_id] = 2);
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'UPDATE', @Actual = @operation;	

END;
