/*


*/

IF OBJECT_ID('dda.set_bypass_triggers_on','P') IS NOT NULL
	DROP PROC dda.[set_bypass_triggers_on];
GO

CREATE PROC dda.[set_bypass_triggers_on]

AS
    SET NOCOUNT ON; 

	-- {copyright}
	
	/* Disallow Explicit User Transactions - i.e., triggers have to be 'turned on/off' outside of a user-enlisted TX: */
	IF @@TRANCOUNT > 0 BEGIN 
		RAISERROR(15002, 16, 1,'dda.bypass_dynamic_triggers');
		RETURN -1;
	END;

	/* If not a member of db_owner, can not execute... */
	IF NOT IS_ROLEMEMBER('db_owner') = 1 BEGIN
		RAISERROR('Procedure dda.bypass_dynamic_triggers may only be called by members of the db_owner role (including members of SysAdmin server-role).', 16, 1);
		RETURN -10;
	END;

	/* Load Current Trigger: */
	DECLARE @definitionID int; 
	DECLARE @definition nvarchar(MAX); 
	
	SELECT @definitionID = [object_id] FROM sys.[triggers] WHERE [name] = N'dynamic_data_auditing_trigger_template' AND [parent_id] = OBJECT_ID('dda.trigger_host');
	IF @definitionID IS NULL BEGIN 
		/* Guessing the chances of this are UNLIKELY (i.e., can't see, say, this SPROC existing but the trigger being gone?), but...still, need to account for this. */
		RAISERROR(N'Dynamic Data Auditing Trigger Template NOT found against table dda.trigger_host. Please re-deploy core DDA plumbing before continuing.', 16, -1);
		RETURN -32; 
	END;	

	SELECT @definition = [definition] FROM sys.[sql_modules] WHERE [object_id] = @definitionID;
	DECLARE @pattern nvarchar(MAX) = N'%IF @context = 0x% BEGIN%';

	/* Extract Context ... (via ugly brute-force approach) ... */
	DECLARE @contextStart int = PATINDEX(@pattern, @definition);
	DECLARE @contextBody nvarchar(MAX) = SUBSTRING(@definition, @contextStart, LEN(@pattern) + 128);
	DECLARE @contextString sysname, @context varbinary(128);

	SET @contextStart = PATINDEX(N'% 0x%', @contextBody);
	SET @contextBody = LTRIM(SUBSTRING(@contextBody, @contextStart, LEN(@contextBody) - @contextStart));
	SET @contextStart = PATINDEX(N'% %', @contextBody);
	SET @contextString = RTRIM(LEFT(@contextBody, @contextStart));
	SET @context = CONVERT(varbinary(128), @contextString, 1);

	/* SET context_info() to bypass value: */
	SET CONTEXT_INFO @context;

	PRINT N'CONTEXT_INFO has been set to value of ' + @contextString + N' - Dynamic Data Audit Triggers will now be bypassed until CONTEXT_INFO is set to another value or the current session is terminated.';

	RETURN 0;
GO