/*


*/

IF OBJECT_ID('dda.enable_dynamic_triggers','P') IS NOT NULL
	DROP PROC dda.[enable_dynamic_triggers];
GO

CREATE PROC dda.[enable_dynamic_triggers]
	@TargetTriggers				nvarchar(MAX)				= N'{ALL}', 
	@ExcludedTriggers			nvarchar(MAX)				= NULL, 
	@PrintOnly					bit							= 1
AS
    SET NOCOUNT ON; 

	-- {copyright}

	SET @TargetTriggers = ISNULL(NULLIF(@TargetTriggers, N''), N'{ALL}');
	SET @ExcludedTriggers = NULLIF(@ExcludedTriggers, N'');
	SET @PrintOnly = ISNULL(@PrintOnly, 1);

	IF @ExcludedTriggers IS NOT NULL AND @TargetTriggers <> N'{ALL}' BEGIN 
		RAISERROR(N'@ExcludedTriggers can ONLY be set when @TargetTriggers is set to the value ''{ALL}'' - i.e., either specify specific triggers for 
			@TargetTriggers by name, or specify ''{ALL}'' + the names of any excluded triggers via @ExcludedTriggers.', 16, 1);
		RETURN -1;
	END;

	CREATE TABLE #dynamic_triggers (
		[parent_table] nvarchar(260) NULL,
		[trigger_name] nvarchar(260) NULL,
		[trigger_version] sysname NULL,
		[custom_trigger_logic] nvarchar(MAX) NULL,
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
		[custom_trigger_logic],
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

	IF @TargetTriggers <> N'{ALL}' BEGIN 
		
		DELETE FROM [#dynamic_triggers] 
		WHERE 
			PARSENAME([trigger_name], 1) NOT IN (
				SELECT 
					PARSENAME([result], 1)
				FROM 
					dda.[split_string](@TargetTriggers, N',', 1)
			);
	END;
	
	IF @ExcludedTriggers IS NOT NULL BEGIN 
		
		DELETE FROM [#dynamic_triggers] 
		WHERE 
			PARSENAME([trigger_name], 1) IN (
				SELECT 
					PARSENAME([result], 1)
				FROM 
					dda.[split_string](@ExcludedTriggers, N',', 1)

			)
	END;

	IF NOT EXISTS (SELECT NULL FROM [#dynamic_triggers]) BEGIN 
		RAISERROR(N'No triggers specified for modification. Either the explicitly named triggers in @TargetTriggers were not matched or, if @TargetTriggers was set to ''{ALL}'', @ExcludedTriggers have removed all potential targets.', 16, 1);
		RETURN -3;
	END;

	IF @PrintOnly = 1 BEGIN 
		PRINT N'-- NOTE: ';
		PRINT N'--		NO COMMANDS or CHANGES have been EXECUTED.';
		PRINT N'--			By DEFAULT, @PrintOnly is set to 1 - meaning that execution will only show what WOULD be changed if @PrintOnly were set to 0.';
		PRINT N'';
		PRINT N'';
	END;

	DECLARE @triggerName sysname, @tableName sysname, @is_disabled bit; 
	DECLARE @sql nvarchar(MAX);

	DECLARE [walker] CURSOR LOCAL FAST_FORWARD FOR 
	SELECT 
		trigger_name, 
		[parent_table],
		[is_disabled]
	FROM 
		[#dynamic_triggers];
	
	OPEN [walker];
	FETCH NEXT FROM [walker] INTO @triggerName, @tableName, @is_disabled;
	
	WHILE @@FETCH_STATUS = 0 BEGIN
	
		IF @is_disabled = 1 BEGIN 
			SET @sql = N'ALTER TABLE ' + @tableName + N' ENABLE TRIGGER ' + PARSENAME(@triggerName, 1) + N';';
			
			IF @PrintOnly = 1 BEGIN 
				PRINT @sql;
			  END;
			ELSE BEGIN 
				EXEC sp_executesql @sql;
			END;
		  END;
		ELSE BEGIN 
			IF @PrintOnly = 0 
				PRINT N'-- Trigger ' + @triggerName + N' is ALREADY enabled. No changes will be made.';
			ELSE 
				PRINT N'-- Trigger' + @triggerName + N' was ALREADY enabled. No changes were made.';
		END;
	
		FETCH NEXT FROM [walker] INTO @triggerName, @tableName, @is_disabled;
	END;
	
	CLOSE [walker];
	DEALLOCATE [walker];

	IF @PrintOnly = 1 BEGIN 
		PRINT N'';
		PRINT N'';
		PRINT N'-- NOTE: '
		PRINT N'--		@PrintOnly is set to 1 - no changes were made.';
	END;

	RETURN 0;
GO