
DROP PROC IF EXISTS dda.enable_table_auditing; 
GO 

CREATE PROC dda.enable_table_auditing 
	@TargetSchema				sysname				= N'dbo', 
	@TargetTable				sysname, 
	@TriggerNamePattern			sysname				= N'ddat_{0}', 
	@SurrogateKeys				nvarchar(260)		= NULL, 
	@PrintOnly					bit					= 0
AS 
	SET NOCOUNT ON; 

	-- {copyright}

	SET @TargetTable = NULLIF(@TargetTable, N'');
	SET @SurrogateKeys = NULLIF(@SurrogateKeys, N'');
	SET @TargetSchema = ISNULL(NULLIF(@TargetSchema, N''), N'dbo');
	SET @TriggerNamePattern = ISNULL(NULLIF(@TriggerNamePattern, N''), N'ddat_{0}');

	-- verify table exists, doesn't already have a dynamic data auditing (DDA) trigger, and has a PK or that we have surrogate info: 
	DECLARE @objectName sysname = QUOTENAME(@TargetSchema) + N'.' + QUOTENAME(@TargetTable);

	IF @objectName IS NULL BEGIN 
		RAISERROR('Invalid (NULL) table or schema name provided. (Provided values were: table -> %s, schema -> %s.)', 16, 1, @TargetTable, @TargetSchema);
		RETURN -1;
	END;

	IF OBJECT_ID(@objectName) IS NULL BEGIN 
		RAISERROR('Invalid Table-Name specified for addition of auditing triggers: %s. Please check your input and try again.', 16, 1);
		RETURN -10;
	END;

	DECLARE @objectID int; 
	SELECT @objectID = object_id FROM sys.objects WHERE [schema_id] = SCHEMA_ID(@TargetSchema) AND [name] = @TargetTable AND [type] = N'U';

	IF EXISTS (
		SELECT NULL 
		FROM sys.[triggers] t INNER JOIN sys.[extended_properties] p ON t.[object_id] = p.[major_id] 
		WHERE t.[parent_id] = @objectID AND p.[name] = N'DDATrigger' AND p.[value] = 'true'
	) BEGIN
		RAISERROR(N'Target Table %s already has a dynamic data auditing (DDA) trigger defined. Please review existing triggers on table.', 16, 1, @objectName);
		RETURN -20;
	END;

	DECLARE @keyColumns nvarchar(MAX) = NULL;
	EXEC dda.[extract_key_columns] 
		@TargetSchema = @TargetSchema, 
		@TargetTable = @TargetTable, 
		@Output = @keyColumns OUTPUT;
	
	IF NULLIF(@keyColumns, N'') IS NULL BEGIN 
		IF @SurrogateKeys IS NOT NULL BEGIN 

			INSERT INTO dda.[surrogate_keys] (
				[schema],
				[table],
				[serialized_surrogate_columns]
			)
			VALUES	(
				@TargetSchema,
				@TargetTable,
				@SurrogateKeys
			);

			PRINT N'NOTE: Added Definition of the following serialized surrogate columns to dda.surrogate_keys for table ' + @objectName + N'; Keys -> ' + @SurrogateKeys + N'.';

			SET @keyColumns = NULL;
			EXEC dda.[extract_key_columns] 
				@TargetSchema = @TargetSchema, 
				@TargetTable = @TargetTable, 
				@Output = @keyColumns OUTPUT;

			IF NULLIF(@keyColumns, N'') IS NOT NULL BEGIN
				GOTO EndChecks;
			END;
		END; 

		RAISERROR(N'Target Table %s does NOT have an Explicit Primary Key defined - nor were @SurrogateKeys provided for configuration/setup.', 16, 1, @objectName);
		RETURN -25;
	END;

EndChecks:
	-- don't allow audits against dda.audits:
	IF LOWER(@objectName) = N'[dda].[audits]' BEGIN 
		RAISERROR(N'Table dda.audits can NOT be the target of auditing (to prevent ''feedback loops'').', 16, 1);
		RETURN -30;
	END;

	-- create the trigger and mark it as a DDA trigger. 
	DECLARE @definitionID int; 
	DECLARE @definition nvarchar(MAX); 
	
	SELECT @definitionID = [object_id] FROM sys.[triggers] WHERE [name] = N'dynamic_data_auditing_trigger_template' AND [parent_id] = OBJECT_ID('dda.trigger_host');

	IF @definitionID IS NULL BEGIN 
		-- guessing the chances of this are UNLIKELY (i.e., can't see, say, this SPROC existing but the trigger being gone?), but...still, need to account for this. 
		RAISERROR(N'Dynamic Data Auditing Trigger Template NOT found against table dda.trigger_host. Please re-deploy DDA plumbing before continuing.', 16, -1);
		RETURN -32; 
	END;

	SELECT @definition = [definition] FROM sys.[sql_modules] WHERE [object_id] = @definitionID;
	DECLARE @pattern nvarchar(MAX) = N'%FOR INSERT, UPDATE, DELETE%';
	DECLARE @bodyStart int = PATINDEX(@pattern, @definition);

	DECLARE @body nvarchar(MAX) = SUBSTRING(@definition, @bodyStart, LEN(@definition) - @bodyStart);

	DECLARE @triggerName sysname; 
	IF @TriggerNamePattern NOT LIKE N'%{0}%' 
		SET @triggerName = @TriggerNamePattern; 
	ELSE 
		SET @triggerName = REPLACE(@TriggerNamePattern, N'{0}', @TargetTable);

	DECLARE @sql nvarchar(MAX) = N'CREATE TRIGGER ' + QUOTENAME(@TargetSchema) + N'.' + QUOTENAME(@triggerName) + N' ON ' + @objectName + N' ' + @body;
	
--EXEC [admindb].dbo.[print_long_string] @sql;

	IF @PrintOnly = 1 BEGIN 
		PRINT @sql;
	  END;
	ELSE BEGIN 
		EXEC sp_executesql @sql;

		DECLARE @latestVersion sysname;
		SELECT @latestVersion = [version_number] FROM dda.version_history WHERE [version_id] = (SELECT MAX(version_id) FROM dda.version_history);

		-- mark the trigger as a DDAT:
		EXEC [sys].[sp_addextendedproperty]
			@name = N'DDATrigger',
			@value = @latestVersion,
			@level0type = 'SCHEMA',
			@level0name = @TargetSchema,
			@level1type = 'TABLE',
			@level1name = @TargetTable,
			@level2type = 'TRIGGER',
			@level2name = @triggerName;
	END;

	RETURN 0;
GO