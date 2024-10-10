
CREATE OR ALTER PROCEDURE [capture].[test update_vs_key_only_is_not_rotate]
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

	-----------------------------------------------------------------------------------------------------------------
	-- Act: 
	-----------------------------------------------------------------------------------------------------------------
	UPDATE [dbo].[KeyOnly] SET [KeyNumber] = 24 WHERE [KeyNumber] = 13;

	UPDATE [dbo].[KeyOnly] SET [KeyNumber] = [KeyNumber] + 10 WHERE [KeyNumber] > 45;

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------

	DECLARE @operation1 sysname = (SELECT [operation] FROM dda.[audits] WHERE [audit_id] = 2);
	EXEC [tSQLt].[AssertEqualsString] @Expected = N'UPDATE', @Actual = @operation1;

END;