DROP PROC IF EXISTS dda.update_trigger_definitions; 
GO 

CREATE PROC dda.update_trigger_definitions 
	@PrintOnly				bit				= 1			-- default to NON-modifying execution (i.e., require explicit change to modify).
AS 
	SET NOCOUNT ON; 

	-- {copyright}

	-- load definition for the NEW trigger:
	DECLARE @definitionID int; 
	DECLARE @definition nvarchar(MAX); 
	
	SELECT @definitionID = [object_id] FROM sys.[triggers] WHERE [name] = N'dynamic_data_auditing_trigger_template' AND [parent_id] = OBJECT_ID('dda.trigger_host');

	IF @definitionID IS NULL BEGIN 
		-- guessing the chances of this are UNLIKELY (i.e., can't see, say, this SPROC existing but the trigger being gone?), but...still, need to account for this. 
		RAISERROR(N'Dynamic Data Auditing Trigger Template NOT found against table dda.trigger_host. Please re-deploy core DDA plumbing before continuing.', 16, -1);
		RETURN -32; 
	END;

	SELECT @definition = [definition] FROM sys.[sql_modules] WHERE [object_id] = @definitionID;
	DECLARE @pattern nvarchar(MAX) = N'%FOR INSERT, UPDATE, DELETE%';
	DECLARE @bodyStart int = PATINDEX(@pattern, @definition);

	DECLARE @body nvarchar(MAX) = SUBSTRING(@definition, @bodyStart, LEN(@definition) - @bodyStart);

	IF @PrintOnly = 1 BEGIN 
		PRINT N'/* ------------------------------------------------------------------------------------------------------------------';
		PRINT N'';
		PRINT N'	NOTE: ';
		PRINT N'		The @PrintOnly parameter for this stored procedure defaults to a value of 1.';
		PRINT N'			Or, in other words, by DEFAULT, this procedure will NOT modify existing triggers.';
		PRINT N'			INSTEAD, it displays which changes it WOULD make - if executed otherwise.';
		PRINT N'';
		PRINT N'		To execute changes (after you''ve reviewed them), explicitly set @PrintOnly = 0. ';
		PRINT N'			EXAMPLE: ';
		PRINT N'				EXEC dda.update_trigger_definitions @PrintOnly = 0;'
		PRINT N'';
		PRINT N'---------------------------------------------------------------------------------------------------------------------';
		PRINT N'*/'
		PRINT N'';
		PRINT N'';

	END;

	CREATE TABLE #dynamic_triggers (
		[parent_table] nvarchar(260) NULL,
		[trigger_name] nvarchar(260) NULL,
		[trigger_version] sysname NULL,
		[for_insert] int NULL,
		[for_update] int NULL,
		[for_delete] int NULL,
		[is_disabled] bit NOT NULL,
		[create_date] datetime NOT NULL,
		[modify_date] datetime NOT NULL,
		[trigger_object_id] int NOT NULL,
		[parent_table_id] int NOT NULL
	);
	
	INSERT INTO [#dynamic_triggers] (
		[parent_table],
		[trigger_name],
		[trigger_version],
		[for_insert],
		[for_update],
		[for_delete],
		[is_disabled],
		[create_date],
		[modify_date],
		[trigger_object_id],
		[parent_table_id]
	)
	EXEC dda.[list_dynamic_triggers];

	IF NOT EXISTS(SELECT NULL FROM [#dynamic_triggers]) BEGIN 
		RAISERROR(N'No tables with dynamic triggers found. Please execute dda.list_dynamic_triggers and/or deploy dynamic triggers before attempting to run updates.', 16, 1);
		RETURN 51;
	END;

	DECLARE @triggerName sysname, @tableName sysname, @triggerVersion sysname;
	DECLARE @disabled bit, @insert bit, @update bit, @delete bit;
	DECLARE @triggerSchemaName sysname, @triggerTableName sysname, @triggerNameOnly sysname;
	
	DECLARE @latestVersion sysname;
	SELECT @latestVersion = [version_number] FROM dda.version_history WHERE [version_id] = (SELECT MAX(version_id) FROM dda.version_history);
	
	DECLARE @firstAs int = PATINDEX(N'%AS%', @body);
	SET @body = SUBSTRING(@body, @firstAs, LEN(@body) - @firstAs);

	DECLARE @scope sysname;
	DECLARE @scopeCount int;
	DECLARE @directive nvarchar(MAX);
	DECLARE @directiveTemplate nvarchar(MAX) = N'ALTER TRIGGER {triggerName} ON {tableName} FOR {scope}
';
	DECLARE @sql nvarchar(MAX);

	DECLARE @errorMessage nvarchar(MAX);
	DECLARE @failures table (
		[failure_id] int IDENTITY(1,1) NOT NULL, 
		[trigger_name] sysname NOT NULL,
		[table_name] sysname NOT NULL, 
		[executed_command] nvarchar(MAX) NOT NULL,
		[error] nvarchar(MAX) NULL 
	);

	DECLARE [cursorName] CURSOR LOCAL FAST_FORWARD FOR 
	SELECT 
		[trigger_name],
		[parent_table],
		[trigger_version],
		[is_disabled],
		[for_insert],
		[for_update],
		[for_delete]
	FROM 
		[#dynamic_triggers];
	
	OPEN [cursorName];
	FETCH NEXT FROM [cursorName] INTO @triggerName, @tableName, @triggerVersion, @disabled, @insert, @update, @delete;
	
	WHILE @@FETCH_STATUS = 0 BEGIN
	
		SET @scope = N'';
		SET @scopeCount = 0;

		IF @insert = 1 BEGIN 
			SET @scope = N'INSERT';
			SET @scopeCount = @scopeCount + 1;
		END;

		IF @update = 1 BEGIN 
			SET @scope = @scope + CASE WHEN @scopeCount > 0 THEN N', ' ELSE N'' END + N'UPDATE';
			SET @scopeCount = @scopeCount + 1;
		END;
		
		IF @delete = 1 BEGIN 
			SET @scope = @scope + CASE WHEN @scopeCount > 0 THEN N', ' ELSE N'' END + N'DELETE';
			SET @scopeCount = @scopeCount + 1;
		END;

		SET @directive = REPLACE(@directiveTemplate, N'{triggerName}', @triggerName);
		SET @directive = REPLACE(@directive, N'{tableName}', @tableName);
		SET @directive = REPLACE(@directive, N'{scope}', @scope);

		IF @scopeCount <> 3 BEGIN 
			PRINT N'WARNING: Non-standard Trigger Scope detected - current sproc is NOT scoped for INSERT, UPDATE, DELETE.';
		END;

		IF @disabled = 1 BEGIN 
			PRINT N'WARNING: Disabled Trigger Detected.';
		END;

		SET @sql = @directive + @body;

		IF @PrintOnly = 1 BEGIN
			PRINT N'-- IF @PrintONly were set to 0, the following change would have been executed: ';
			PRINT @directive + N' AS ..... <updated_trigger_body_here>...';
			PRINT N''
		  END; 
		ELSE BEGIN 
		
			BEGIN TRY
				BEGIN TRAN;

					EXEC sp_executesql 
						@sql;

					IF @triggerVersion <> @latestVersion BEGIN 
						
						SELECT 
							@triggerSchemaName = PARSENAME(@tableName, 2), 
							@triggerTableName = PARSENAME(@tableName, 1), 
							@triggerNameOnly = PARSENAME(@triggerName, 1);

						-- update version in meta-data/extended properties: 
						EXEC sys.[sp_updateextendedproperty]
							@name = N'DDATrigger',
							@value = @latestVersion,
							@level0type = 'SCHEMA',
							@level0name = @triggerSchemaName,
							@level1type = 'TABLE',
							@level1name = @triggerTableName,
							@level2type = 'TRIGGER',
							@level2name = @triggerNameOnly;

						PRINT N'Updated ' + @triggerName + N' on ' + @tableName + N' from version ' + @triggerVersion + N' to version ' + @latestVersion + N'.';
					  END;
					ELSE BEGIN 
						--PRINT N'Updated ' + @triggerName + N' on ' + @tableName + N'....';
						PRINT N'Updated ' + @triggerName + N' on ' + @tableName + N' to version ' + @latestVersion + N'.';
					END;
				
				COMMIT;

			END TRY
			BEGIN CATCH 
				
				ROLLBACK;
				
				SELECT @errorMessage = CONCAT(N'Error Number: ', ERROR_NUMBER(), N'. Line: ', ERROR_LINE(), N'. Error Message: ' + ERROR_MESSAGE());
				INSERT INTO @failures (
					[trigger_name],
					[table_name],
					[executed_command],
					[error]
				)
				VALUES	(
					@triggerName, 
					@tableName, 
					@sql,
					@errorMessage
				);

			END CATCH;

		END;
	
		FETCH NEXT FROM [cursorName] INTO @triggerName, @tableName, @triggerVersion, @disabled, @insert, @update, @delete;
	END;
	
	CLOSE [cursorName];
	DEALLOCATE [cursorName];
	
	IF EXISTS (SELECT NULL FROM @failures) BEGIN 
		
		SELECT 'The following Errors were Encountered. Please review and correct.' [Deployment Warning!!!];

		SELECT
			[trigger_name],
			[table_name],
			[executed_command],
			[error]
		FROM 
			@failures
		ORDER BY 
			[failure_id];

	END;

	RETURN 0;
GO