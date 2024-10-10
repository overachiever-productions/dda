
CREATE OR ALTER PROCEDURE [capture].[test update_vs_multiple_row_keys_is_mutate]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	EXEC [tSQLt].[FakeTable] 
		@TableName = N'dda.audits', 
		@Identity = 1;

	EXEC [tSQLt].[FakeTable] 
		@TableName = N'dbo.KeyOnly', 
		@Identity = 1;

	EXEC [tSQLt].[ApplyTrigger] 
		@TableName = N'dbo.KeyOnly', 
		@TriggerName = N'ddat_KeyOnly';

	EXEC [tSQLt].[ApplyConstraint] 
		@TableName = N'dbo.KeyOnly', 
		@ConstraintName = N'PK_KeyOnly';

	INSERT INTO [dbo].[KeyOnly] ([KeyNumber]) VALUES (13);

	INSERT INTO [dbo].[KeyOnly] ([KeyNumber])
	VALUES	
		(50),
		(51),
		(52);

	-----------------------------------------------------------------------------------------------------------------
	-- Act: 
	-----------------------------------------------------------------------------------------------------------------
	UPDATE [dbo].[KeyOnly] SET [KeyNumber] = 24 WHERE [KeyNumber] = 13;

	UPDATE [dbo].[KeyOnly] SET [KeyNumber] = [KeyNumber] + 10 WHERE [KeyNumber] > 45;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------

	DECLARE @operation1 sysname = (SELECT [operation] FROM dda.[audits] WHERE [audit_id] = 3);
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'UPDATE', @Actual = @operation1;

	DECLARE @operation2 sysname = (SELECT [operation] FROM dda.[audits] WHERE [audit_id] = 4);
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'MUTATE', @Actual = @operation2;

END;