/*
	SIGNATURE:
		EXEC [dda].[enable_database_auditing] 
			@ExcludedTables = N'dbo.shredded, dda.another_table, [dbo].[_SCSActivities], [dbo].[HomeSlice]  ', 
			@ExcludeTablesWithoutPKs = 1,
			@ContinueOnError = 1;

*/

IF OBJECT_ID('dda.enable_database_auditing','P') IS NOT NULL
	DROP PROC dda.[enable_database_auditing];
GO

CREATE PROC dda.[enable_database_auditing]
	@ExcludedTables				nvarchar(MAX), 
	@ExcludeTablesWithoutPKs	bigint					= 0,			-- Default behavior is to throw an error/warning - and stop. 
	@TriggerNamePattern			sysname					= N'ddat_{0}', 
	@ContinueOnError			bit						= 1,
	@PrintOnly					bit						= 0
AS
    SET NOCOUNT ON; 

	-- {copyright}
	
	SET @ExcludedTables = NULLIF(@ExcludedTables, N'');
	SET @TriggerNamePattern = ISNULL(NULLIF(@TriggerNamePattern, N''), N'ddat_{0}');
	SET @ExcludeTablesWithoutPKs = ISNULL(@ExcludeTablesWithoutPKs, 0);
	SET @ContinueOnError = ISNULL(@ContinueOnError, 1);
	SET @PrintOnly = ISNULL(@PrintOnly, 0);

	-- check for tables without PKs (that aren't in the list of exclusions):
	DECLARE @exclusions table (
		[row_id] int NOT NULL, 
		[schema_name] sysname NULL,
		[table_name] sysname NOT NULL
	);

	INSERT INTO @exclusions (
		[row_id],
		[table_name]
	)
	SELECT 
		[row_id], 
		[result]
	FROM 
		dda.[split_string](@ExcludedTables, N',', 1);

	IF EXISTS (SELECT NULL FROM @exclusions) BEGIN
		UPDATE @exclusions 
		SET 
			[schema_name] = ISNULL(PARSENAME([table_name], 2), N'dbo'), 
			[table_name] = PARSENAME([table_name], 1);
	END;

	DECLARE @nonExcludedTablesWithoutPKs table (
		[table_id] int IDENTITY(1,1) NOT NULL, 
		[schema_name] sysname NOT NULL, 
		[table_name] sysname NOT NULL
	);

	INSERT INTO @nonExcludedTablesWithoutPKs (
		[schema_name],
		[table_name]
	)
	SELECT 
		SCHEMA_NAME([t].[schema_id]) [schema_name],
		[t].[name] [table_name]
	FROM 
		sys.[tables] [t]
		LEFT OUTER JOIN @exclusions [e] ON SCHEMA_NAME([t].[schema_id]) = [e].[schema_name] AND [t].[name] = [e].[table_name]
	WHERE 
		[type] = N'U'
		AND OBJECTPROPERTYEX([object_id], N'TableHasPrimaryKey') = 0
		AND [e].[table_name] IS NULL;

	DELETE x 
	FROM 
		@nonExcludedTablesWithoutPKs x 
		LEFT OUTER JOIN dda.[surrogate_keys] k ON [x].[schema_name] = k.[schema] AND x.[table_name] = k.[table]
	WHERE
		[k].[surrogate_id] IS NOT NULL;

	-- yeah... don't fail things cuz of this guy:
	DELETE FROM @nonExcludedTablesWithoutPKs WHERE [schema_name] = N'dda' AND [table_name] = N'trigger_host';

	DECLARE @serializedNonPKTables nvarchar(MAX) = N'';
	IF EXISTS (SELECT NULL FROM @nonExcludedTablesWithoutPKs) BEGIN 
		SELECT 
			@serializedNonPKTables	= @serializedNonPKTables + QUOTENAME([schema_name]) + N'.' + QUOTENAME([table_name]) + N' 
		'  -- INTENTIONAL carriage return (and 2x TAB chars) = cheat/hack for formatting output below (and work on BOTH Windows and Linux).
		FROM 
			@nonExcludedTablesWithoutPKs 
		ORDER BY 
			[table_id];

		SET @serializedNonPKTables = LEFT(@serializedNonPKTables, LEN(@serializedNonPKTables) - 4);

		IF @ExcludeTablesWithoutPKs = 0 BEGIN
			PRINT N'ERROR:';
			PRINT N'	Tables without Primary Keys were detected and were NOT EXCLUDED from processing.';
			PRINT N'		Each table to be audited must EITHER have an explicit Primary Key - or a ''work-around''/surrogate key.';
			PRINT N'';
			PRINT N'	The following tables do NOT have Primary Keys and were NOT excluded from processing:';
			PRINT N'		' + @serializedNonPKTables;
			PRINT N'';
			PRINT N'';
			PRINT N'	To continue, do ONE OR MORE of the following: ';
			PRINT N'		- [RECOMMENDED]: Add Primary Keys to all tables listed above. ';
			PRINT N'		- [WORK-AROUND]: Add surrogate ''keys'' for any of the tables above to the dda.surrogate_keys table ';
			PRINT N'				where a PK might not currently make sense.';
			PRINT N'		- [WORK-AROUND]: Explicitly exclude any of the tables listed above via the @ExcludedTables parameter - for any ';
			PRINT N'				tables you do NOT wish to track changes against (i.e., those without a PK or surrogate key defined.';
			PRINT N'					EXAMPLE: @ExcludedTables = N''dbo.someTableHere, dbo.AnotherTableHere, etc.'' -- (schema-names optional).';
			PRINT N'		- [WORK-AROUND]: Set @ExcludeTablesWithoutPKs = 1 - and all tables without a PK will be skipped during processing.';
			PRINT N'				NOTE: a list of non-tracked tables WILL be output at the end of processing/execution.';
			PRINT N'';
			PRINT N'';

			RETURN 0;
		END;
	END;

	-- If we're still here, all tables either have FKs, surrogates, or have been explicitly or 'auto' excluded - i..e, time to add triggers:
	CREATE TABLE #tablesToAudit (
		row_id	int IDENTITY(1,1) NOT NULL, 
		[object_id] int NOT NULL, 
		[schema_name] sysname NOT NULL, 
		[table_name] sysname NOT NULL, 
		[existing_trigger] sysname NULL, 
		[existing_version] sysname NULL, -- vNEXT: populate this and use it to inform 'callers' or any version 'discrepencies'. 
		[is_disabled] bit NOT NULL DEFAULT (0),
		[is_not_insert_update_deleted] bit NOT NULL DEFAULT (0),
		[error_details] nvarchar(MAX) NULL 
	);

	INSERT INTO [#tablesToAudit] (
		[object_id],
		[schema_name],
		[table_name]
	)
	SELECT 
		[object_id], 
		SCHEMA_NAME([schema_id]) [schema_name],
		[name] [table_name]
	FROM 
		sys.[objects]
	WHERE 
		[type] = 'U'
	ORDER BY 
		[name];

	DELETE x 
	FROM 
		[#tablesToAudit] x 
		LEFT OUTER JOIN (
			SELECT 
				[row_id] [id],
				[schema_name], 
				[table_name]
			FROM 
				@exclusions

			UNION

			SELECT 
				[table_id] [id], 
				[schema_name], 
				[table_name]
			FROM 
				@nonExcludedTablesWithoutPKs

		) exclusions ON [x].[schema_name] = [exclusions].[schema_name] AND [x].[table_name] = [exclusions].[table_name]
	WHERE 
		-- Exclude DDA tables:
		(x.[schema_name] = N'dda' AND (x.[table_name] = N'trigger_host' OR x.[table_name] = N'audits'))
		OR [exclusions].[id] IS NOT NULL;

	-- flag/remove tables already enabled for auditing:
	WITH core AS (  -- NOTE: this is a DRY violation - from dda.list_dynamic_triggers
		SELECT 
			(SELECT SCHEMA_NAME(o.[schema_id]) + N'.' + OBJECT_NAME(o.[object_id]) FROM sys.objects o WHERE o.[object_id] = t.[parent_id]) [parent_table],
			(SELECT QUOTENAME(SCHEMA_NAME(o.[schema_id])) + N'.' + QUOTENAME(t.[name]) FROM sys.objects o WHERE o.[object_id] = t.[object_id]) [trigger_name],
			(SELECT CASE WHEN EXISTS (SELECT NULL FROM sys.[trigger_events] e WHERE e.[object_id] = t.[object_id] AND [e].[type] = 1) THEN 1 ELSE 0 END) [for_insert],
			(SELECT CASE WHEN EXISTS (SELECT NULL FROM sys.[trigger_events] e WHERE e.[object_id] = t.[object_id] AND [e].[type] = 2) THEN 1 ELSE 0 END) [for_update],
			(SELECT CASE WHEN EXISTS (SELECT NULL FROM sys.[trigger_events] e WHERE e.[object_id] = t.[object_id] AND [e].[type] = 3) THEN 1 ELSE 0 END) [for_delete],
			[t].[is_disabled]
		FROM 
			sys.triggers t
			INNER JOIN sys.[extended_properties] p ON t.[object_id] = p.[major_id]
		WHERE 
			p.[name] = N'DDATrigger' AND p.[value] = 'true'
			AND 
				t.[parent_id] <> (SELECT [object_id] FROM sys.objects WHERE [schema_id] = SCHEMA_ID('dda') AND [name] = N'trigger_host')
	)
	
	UPDATE x 
	SET 
		x.[existing_trigger] = t.[trigger_name], 
		x.[is_disabled] = t.[is_disabled], 
		x.[is_not_insert_update_deleted] = t.[is_non_standard]
	FROM 
		[#tablesToAudit] x 
		INNER JOIN (
			SELECT 
				PARSENAME([parent_table], 2) [schema_name],
				PARSENAME([parent_table], 1) [table_name],
				[trigger_name], 
				[is_disabled], 
				CASE 
					WHEN [for_insert] = 0 OR [for_update] = 0 OR [for_delete] = 0 THEN 1
					ELSE 0 
				END [is_non_standard]
			FROM 
				core
		) t ON [x].[schema_name] = [t].[schema_name] AND [x].[table_name] = [t].[table_name];

	DECLARE @row_id int, @schemaName sysname, @tableName sysname; 
	DECLARE @outcome int; 
	DECLARE @error nvarchar(MAX);

	DECLARE [cursorName] CURSOR LOCAL FAST_FORWARD FOR 
	SELECT 
		[row_id], 
		[schema_name], 
		[table_name]
	FROM 
		[#tablesToAudit] 
	WHERE 
		[existing_trigger] IS NULL
	ORDER BY 
		[row_id];
	
	OPEN [cursorName];
	FETCH NEXT FROM [cursorName] INTO @row_id, @schemaName, @tableName;
	
	WHILE @@FETCH_STATUS = 0 BEGIN

		IF @PrintOnly = 1 BEGIN 
			PRINT '... processing for ' + QUOTENAME(@schemaName) + N'.' + QUOTENAME(@tableName) + N' would happen here (@PrintOnly = 1) ....';
		  END; 
		ELSE BEGIN 
			BEGIN TRY 
				BEGIN TRAN;
					SET @outcome = 0;

					EXEC @outcome = dda.[enable_table_auditing] 
						@TargetSchema = @schemaName, 
						@TargetTable = @tableName, 
						@TriggerNamePattern = @TriggerNamePattern, 
						@PrintOnly = 0;

					IF @outcome <> 0 
						RAISERROR('Unexpected Error. No exceptions detected, but execution of dda.enable_table_auditing did NOT RETURN 0.', 16, 1);
				COMMIT;

			END TRY 
			BEGIN CATCH 
				SELECT @error = ERROR_MESSAGE();

				IF @@TRANCOUNT > 0 ROLLBACK;

				UPDATE [#tablesToAudit]
				SET 
					[error_details] = @error 
				WHERE 
					[row_id] = @row_id;

				IF @ContinueOnError = 0 BEGIN 
					RAISERROR('Processing Error Encountered. Excution/Addition of triggers terminated.', 16, 1);
					GOTO Reporting;
				END;

			END CATCH;
		END;
	
		FETCH NEXT FROM [cursorName] INTO @row_id, @schemaName, @tableName;
	END;
	
	CLOSE [cursorName];
	DEALLOCATE [cursorName];

Reporting:
	IF @PrintOnly = 1 BEGIN 
		PRINT N'';
	END;

	IF OBJECT_ID(N'tempdb..#tablesToAudit') IS NOT NULL AND EXISTS (SELECT NULL FROM [#tablesToAudit] WHERE [error_details] IS NOT NULL) BEGIN 
		
		RAISERROR('Errors were encountered during execution.', 16, 1);
		PRINT N'ERROR:'; 
		PRINT N'	The following errors occured:'; 
		PRINT N'';

		-- bletch, cursors are ugly, but: 
		DECLARE [walker] CURSOR LOCAL FAST_FORWARD FOR 
		SELECT 
			[schema_name], 
			[table_name], 
			[error_details]
		FROM 
			[#tablesToAudit] 
		WHERE 
			[error_details] IS NOT NULL
		ORDER BY 
			[row_id];
		
		OPEN [walker];
		FETCH NEXT FROM [walker] INTO @schemaName, @tableName, @error;
		
		WHILE @@FETCH_STATUS = 0 BEGIN
		
			PRINT N'		' + QUOTENAME(@schemaName) + N'.' + QUOTENAME(@tableName);
			PRINT N'			' + @error;
		
			FETCH NEXT FROM [walker] INTO @schemaName, @tableName, @error;
		END;
		
		CLOSE [walker];
		DEALLOCATE [walker];

		PRINT N'';

	END;	

	IF OBJECT_ID(N'tempdb..#tablesToAudit') IS NOT NULL AND EXISTS (SELECT NULL FROM [#tablesToAudit] WHERE [existing_trigger] IS NOT NULL) BEGIN 
		DECLARE @triggerName sysname;
		DECLARE @isDisabled bit; 
		DECLARE @isNonStandard bit;

		PRINT N'NOTE:';
		PRINT N'';
		PRINT N'	The following tables ALREADY have/had dynamic triggers defined (and were SKIPPED):';
		PRINT N'';

		-- bletch, cursors are ugly, but: 
		DECLARE [walker] CURSOR LOCAL FAST_FORWARD FOR 
		SELECT 
			[schema_name], 
			[table_name], 
			[existing_trigger], 
			[is_disabled], 
			[is_not_insert_update_deleted]
		FROM 
			[#tablesToAudit] 
		WHERE 
			[existing_trigger] IS NOT NULL 
		ORDER BY 
			[row_id];
		
		OPEN [walker];
		FETCH NEXT FROM [walker] INTO @schemaName, @tableName, @triggerName, @isDisabled, @isNonStandard;
		
		WHILE @@FETCH_STATUS = 0 BEGIN
		
			PRINT N'		' + QUOTENAME(@schemaName) + N'.' + QUOTENAME(@tableName) + N' -> ' + @triggerName;

			IF @isDisabled = 1 BEGIN 
				PRINT N'			WARNING: Trigger ' + @triggerName + N' IS currently DISABLED.';
			END;


			IF @isNonStandard = 1 BEGIN
				PRINT N'			NOTE: Trigger ' + @triggerName + N' IS _NOT_ configured for ALL operation types (INSERT, UPDATE, DELETE - i.e., one or more operations is NOT enabled).'

			END;




			FETCH NEXT FROM [walker] INTO @schemaName, @tableName, @triggerName, @isDisabled, @isNonStandard;
		END;
		
		CLOSE [walker];
		DEALLOCATE [walker];

		PRINT N'';
		PRINT N'	To UPDATE code within existing dynamic triggers, use dda.update_trigger_definitions.';
		PRINT N'';

	END;
	
	IF EXISTS (SELECT NULL FROM @exclusions) BEGIN 
		DECLARE @serializedExclusions nvarchar(MAX) = N'';

		SELECT 
			@serializedExclusions = @serializedExclusions +  QUOTENAME([schema_name]) + N'.' + QUOTENAME([table_name]) + N' 
		'  -- INTENTIONAL carriage return (and 2x TAB chars) = cheat/hack for formatting output below (and work on BOTH Windows and Linux).
		FROM 
			@exclusions;

		SET @serializedExclusions = LEFT(@serializedExclusions, LEN(@serializedExclusions) - 4);

		PRINT N'NOTE:';
		PRINT N'	The following tables were EXPLICITLY excluded from processing, and have not been enabled for auditing:';
		PRINT N'		' + @serializedExclusions; 
		PRINT N'';

	END;

	IF NULLIF(@serializedNonPKTables, N'') IS NOT NULL BEGIN 
		PRINT N'NOTE: ';
		PRINT N'	The following tables DO NOT have Primary Keys defined and were not EXPLICITLY excluded from auditing: ';
		PRINT N'		' + @serializedNonPKTables;
		PRINT N'';
		PRINT N'	Please review the tables listed above, and if you wish to audit any of them, either add PKs, define a surrogate ';
		PRINT N'		set of keys via INSERTs into dda.surrogate_keys, then re-run execution/deployment.';
		PRINT N'';
	END;

	RETURN 0;
GO