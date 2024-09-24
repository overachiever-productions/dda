/*
	EXAMPLES: 
	
			EXEC Meddling.dda.get_table_history 
				@TargetTable = N'login_metrics', 
				@StartAuditID = 1113
				,@EndAuditID = 1121
				,@TransformOutput = 0


*/

CREATE OR ALTER PROC dda.get_table_history 
	@TargetTable					sysname			= NULL,				-- can include schema name if desired - i.e., N'dbo.SortTable' is valid 
	--@TargetTableSchema				sysname			= N'dbo',		
	@StartTime						datetime		= NULL, 
	@EndTime						datetime		= NULL, 
	@TargetLogins					nvarchar(MAX)	= NULL, 
	@StartAuditID					int				= NULL,
	@EndAuditID						int				= NULL,
	@StartTransactionID				sysname			= NULL, 
	@EndTransactionID				sysname			= NULL,
	@TransactionDate				date			= NULL,
	@TransformOutput				bit				= 0,				-- defaults to NOT transforming (unlike dda.get_audit_data)
	@FromIndex						int				= 1, 
	@ToIndex						int				= 100, 
	@ViewType						sysname			= N'REPORT'			-- options are { GRID | REPORT }
AS 
	SET NOCOUNT ON;

	SET @TargetTable = NULLIF(@TargetTable, N'');
	DECLARE @tableID int, @schemaName sysname, @tableName sysname;

	IF @TargetTable IS NULL BEGIN 
		RAISERROR(N'Invalid @TargetTable name specified. This parameter can NOT be NULL or empty.', 16, 1);
		RETURN -100;
	  END; 
	ELSE BEGIN
		/* This code, interestingly enough, accounts for tables [withcommas,inTheName] by means of seeing if the table exists. */
		 SELECT @tableID = OBJECT_ID(@TargetTable, N'U');
		IF @tableID IS NULL BEGIN 
			RAISERROR(N'Invalid @TargetTable name specified. A table with the name [%s] does NOT exist.', 16, 1, @TargetTable);
			RETURN -101;
		END;
	END;

	/* Standardize target details .... */
	SELECT @tableName = PARSENAME(OBJECT_NAME(@tableId), 1);
	SELECT @schemaName = SCHEMA_NAME([schema_id]) FROM sys.[objects] WHERE [object_id] = @tableID;
	DECLARE @ddaStyleFullTableName sysname = @schemaName + N'.' + @tableName;
		
	CREATE TABLE [#audit_data] ( 
		[row_number] int NOT NULL,
		[total_rows] int NOT NULL, 
		[audit_id] int NOT NULL,
		[timestamp] datetime NOT NULL,
		[original_login] sysname NOT NULL,
		[table] sysname NOT NULL,
		[transaction_id] sysname NOT NULL,
		[operation_type] char(9) NOT NULL,
		[row_count] int NOT NULL,
		[change_details] nvarchar(max) NULL
	);

	DECLARE @getAuditDataResult int;
	INSERT INTO [#audit_data] (
		[row_number],
		[total_rows],
		[audit_id],
		[timestamp],
		[original_login],
		[table],
		[transaction_id],
		[operation_type],
		[row_count],
		[change_details]
	)
	EXEC @getAuditDataResult = dda.[get_audit_data]
		@StartTime = @StartTime,
		@EndTime = @EndTime,
		@TargetLogins = @TargetLogins,
		@TargetTables = @tableName,  /* use the cleaned (table only) name of the table... */
		@StartAuditID = @StartAuditID,
		@EndAuditID = @EndAuditID,
		@StartTransactionID = @StartTransactionID,
		@EndTransactionID = @EndTransactionID,
		@TransactionDate = @TransactionDate,
		@TransformOutput = @TransformOutput,
		@FromIndex = @FromIndex,
		@ToIndex = @ToIndex;

	IF @getAuditDataResult <> 0 BEGIN  /* Validation error messages have already been printed/output - so just RETURN the error value. */
		RETURN 100 + @getAuditDataResult; 
	END;

	/* Because @TargetTable is REQUIRED, the check below is not necessary. BUT: leaving it in case I remove @TargetTable requirement. */
	IF (SELECT COUNT(DISTINCT [table]) FROM [#audit_data]) > 1 BEGIN 
		RAISERROR('Audit details for [dda].[get_table_history] can ONLY contain results from a SINGLE table.', 16, 1);
		RETURN -102;
	END;

	/* Extract Column Names for Audited Table: */
	SELECT 
		[c].[column_id],
		[c].[name],
		[c].[name] [original_name],
		TYPE_NAME([c].[system_type_id]) + 
		CASE 
			WHEN TYPE_NAME([c].[system_type_id]) LIKE 'var%' OR [c].[max_length] LIKE '%char%' THEN N' (' + CASE WHEN [c].[max_length] > 0 THEN CAST([c].[max_length] AS sysname) ELSE N'max' END + N')' 
			WHEN TYPE_NAME([c].[system_type_id]) = 'datetime2' THEN N' (' + CAST([c].[scale] AS sysname) + N')'
			WHEN TYPE_NAME([c].[system_type_id]) IN ('decimal', 'numeric') THEN N'(' + CAST([c].[precision] AS sysname) + N', ' + CAST([c].[scale] AS sysname) + N')'
			ELSE N''
		END [data_type], 
		[c].[is_nullable]
	INTO 
		#auditedTableColumns
	FROM 
		sys.[all_columns] c 
	WHERE 
		[c].[object_id] = OBJECT_ID(@TargetTable);

	/* Map Column Names if/as needed: */
	DECLARE @fullTableName sysname = REPLACE(REPLACE(@schemaName + N'.' + @TargetTable, N']', N''), N']', N'');
	IF EXISTS (SELECT NULL FROM [dda].[translation_columns] WHERE LOWER([table_name]) = LOWER(@fullTableName)) BEGIN 
		UPDATE x 
		SET 
			x.[name] = tc.[translated_name]
		FROM 
			[#auditedTableColumns] x  
			INNER JOIN dda.[translation_columns] tc ON LOWER(x.[name]) = LOWER(tc.[column_name])
		WHERE 
			LOWER(tc.[table_name]) = LOWER(@fullTableName);
	END;

	DECLARE @tableKeys nvarchar(MAX);
	EXEC dda.[extract_key_columns] 
		@TargetSchema = @schemaName, 
		@TargetTable = @tableName, 
		@Output = @tableKeys OUTPUT;

	DECLARE @newline nchar(2) = NCHAR(13) + NCHAR(10);
	DECLARE @tab nchar(1) = NCHAR(9);
	DECLARE @alterForKeyCols nvarchar(MAX) = N'';
	DECLARE @insertAndSelectKeyCols nvarchar(MAX) = N'';
	DECLARE @jsonKeyColsMapping nvarchar(MAX) = N'';

	SELECT 
		@alterForKeyCols = @alterForKeyCols + @newline + N'ALTER TABLE [#audit_data_rows] ADD ' + QUOTENAME([c].[name]) + N' ' + [c].[data_type] + N' NULL; ', 
		@insertAndSelectKeyCols = @insertAndSelectKeyCols + @newline + @tab + @tab + N'[y].' + QUOTENAME([c].[name]) + N', ',
		@jsonKeyColsMapping = @jsonKeyColsMapping + @newline + @tab + @tab + @tab + QUOTENAME([c].[name]) + N' ' + [c].[data_type] + N' N''$.' + [c].[name] +''', '
	FROM 
		[#auditedTableColumns] [c]
		INNER JOIN dda.[split_string](@tableKeys, N',', 1) k ON [c].[name] = [k].[result]
	ORDER BY 
		[c].[column_id]

	IF @jsonKeyColsMapping <> N'' BEGIN
		SET @jsonKeyColsMapping = LEFT(@jsonKeyColsMapping, LEN(@jsonKeyColsMapping) - 1);
	END;

	/* ALLOW for option to Map Data Changes if/as needed. */
	DECLARE @transformOutputAlterTemplate nvarchar(MAX) = N'';
	DECLARE @transformOutputColumnNames nvarchar(MAX) = N'';
	IF @TransformOutput = 1 BEGIN 

		SELECT 
			@transformOutputAlterTemplate = @transformOutputAlterTemplate + @newline +  N'ALTER TABLE [#projection] ALTER COLUMN ' + QUOTENAME([a].[name]) + ' {newType} NULL;',
			@transformOutputColumnNames = @transformOutputColumnNames + QUOTENAME([a].[name]) + N','
		FROM 
			[#auditedTableColumns] [a]
			INNER JOIN dda.[translation_values] [t] ON [a].[original_name] = [t].[column_name] AND [t].[table_name] = @ddaStyleFullTableName;

		IF @transformOutputColumnNames <> N'' 
			SET @transformOutputColumnNames = LEFT(@transformOutputColumnNames, LEN(@transformOutputColumnNames) - 1);
	END;

	CREATE TABLE [#audit_data_rows] (
		[dda.row_id] int IDENTITY(1,1) NOT NULL,
		[dda.audit_id] int NOT NULL,
		[dda.row_audit_id] int NOT NULL
	);

	EXEC sys.[sp_executesql]
		@alterForKeyCols;

	EXEC sys.[sp_executesql]
		N'ALTER TABLE [#audit_data_rows] ADD [dda.json_row] nvarchar(MAX) NULL; ';

	DECLARE @dynamicRowProjection nvarchar(MAX) = N'
	INSERT INTO [#audit_data_rows] (
		[dda.audit_id],
		[dda.row_audit_id], {keyColsInsert}
		[dda.json_row]
	)
	SELECT 
		[a].[audit_id], 
		([x].[Key] + 1) [dda.row_audit_id], {keyColsSelect}
		[x].[Value] [dda.json_row]
	FROM 
		[#audit_data] [a] 
		CROSS APPLY OPENJSON(JSON_QUERY([a].[change_details], N''$'')) x
		CROSS APPLY OPENJSON([x].[Value], N''$.key'') WITH ( {jsonCols}
		) y
	ORDER BY 
		[a].[audit_id], [x].[Key]; ';

	SET @dynamicRowProjection = REPLACE(@dynamicRowProjection, N'{keyColsInsert}', REPLACE(@insertAndSelectKeyCols, N'[y].[', N'['));
	SET @dynamicRowProjection = REPLACE(@dynamicRowProjection, N'{keyColsSelect}', @insertAndSelectKeyCols);
	SET @dynamicRowProjection = REPLACE(@dynamicRowProjection, N'{jsonCols}', @jsonKeyColsMapping);

	EXEC sys.sp_executesql 
		@dynamicRowProjection;

	/* Now that we've gotten each ROW _AND_ its key(s) ... time to start extracting actual changed values... */
	CREATE TABLE #projection (
		[dda.audit_id] int NOT NULL, 
		[dda.timestamp] datetime NOT NULL, 
		[dda.original_login] sysname NOT NULL, 
		--[dda.transaction_id] sysname NOT NULL, 
		[dda.operation_type] sysname NOT NULL, 
		[dda.row_count] int NOT NULL,
		[dda.row_audit_id] int NOT NULL,		
		[dda.level] sysname NOT NULL,
		[ =>] char(1) NOT NULL DEFAULT N''
	);

	DECLARE @alterAddColumns nvarchar(MAX) = N'';
	DECLARE @insertAndSelectColumns nvarchar(MAX) = N'';
	DECLARE @jsonMappingCols nvarchar(MAX) = N'';

	SELECT 
		@alterAddColumns = @alterAddColumns + @newline + N'ALTER TABLE [#projection] ADD ' + QUOTENAME([name]) + N' ' + [data_type] + N' NULL;', 
		@insertAndSelectColumns = @insertAndSelectColumns + @newline + @tab + @tab + N'[y].' +  QUOTENAME([name]) + N',', 
		@jsonMappingCols = @jsonMappingCols + @newline + @tab + @tab + @tab + QUOTENAME([name]) + N' ' + [a].[data_type] + @tab + N'N''$.' + [name] + N'.~loc~'','
	FROM 
		[#auditedTableColumns] [a]
	WHERE
		[a].[name] NOT IN (SELECT [result] FROM dda.[split_string](@tableKeys, N',', 1))
	ORDER BY 
		[a].[column_id];

	IF NULLIF(@alterAddColumns, N'') IS NOT NULL BEGIN
		SET @alterAddColumns = LEFT(@alterAddColumns, LEN(@alterAddColumns) - 1);
		SET @jsonMappingCols = LEFT(@jsonMappingCols, LEN(@jsonMappingCols) -1);
	END;

	/* Add KEY cols, then add Value cols: */
	SET @alterForKeyCols = REPLACE(@alterForKeyCols, N'ALTER TABLE [#audit_data_rows] ADD ', N'ALTER TABLE [#projection] ADD ');
	EXEC sys.[sp_executesql]
		@alterForKeyCols;

	EXEC sys.[sp_executesql]
		@alterAddColumns;

	DECLARE @dynamicProjectionSql nvarchar(MAX) = N'
	INSERT INTO [#projection] (
		[dda.audit_id], 
		[dda.original_login], 
		--[dda.transaction_id], 
		[dda.operation_type],
		[dda.row_count],
		[dda.row_audit_id],
		[dda.level], {insertKeyCols}{insertCols}
		[dda.timestamp]
	)
	SELECT 
		[r].[dda.audit_id],
		[a].[original_login] [dda.original_login],
		--[a].[transaction_id] [dda.transaction_id],
		[a].[operation_type] [dda.operation_type],
		[a].[row_count] [dda.row_count],
		[r].[dda.row_audit_id], 
		''{level}'' [dda.level],{selectKeyCols}{selectCols}
		[a].[timestamp] [dda.timestamp]
	FROM 
		[#audit_data_rows] [r]
		INNER JOIN [#audit_data] [a] ON [r].[dda.audit_id] = [a].[audit_id]
		CROSS APPLY OPENJSON([r].[dda.json_row], N''$.detail'') WITH ({jsonMapping}
		) [y]
	WHERE 
		[a].[operation_type] IN ({operation})
	ORDER BY 
		[r].[dda.audit_id], [r].[dda.row_audit_id]; ';

	/* Setup projection details for all transforms/operations: */
	SET @dynamicProjectionSql = REPLACE(@dynamicProjectionSql, N'{selectCols}', @insertAndSelectColumns);
	SET @dynamicProjectionSql = REPLACE(@dynamicProjectionSql, N'{insertKeyCols}', REPLACE(@insertAndSelectKeyCols, N'[y].[', N'['));
	SET @dynamicProjectionSql = REPLACE(@dynamicProjectionSql, N'{insertCols}', REPLACE(@insertAndSelectColumns, N'[y].[', N'['));
	SET @dynamicProjectionSql = REPLACE(@dynamicProjectionSql, N'{selectKeyCols}', REPLACE(@insertAndSelectKeyCols, N'[y].[', N'[r].['));

	/* Execute projections for INSERT + DELETE and then for before/after UPDATES: */
	DECLARE @errorMessage nvarchar(MAX);
	DECLARE @errorID int;
	DECLARE @conversionErrorCount int = 0;

EXECUTE_PROJECTION:
	TRUNCATE TABLE [#projection];
	
	IF @conversionErrorCount > 0 BEGIN 
		DECLARE @typeConversionAlter nvarchar(MAX);
		DECLARE @targetType sysname = N'[sysname]';
		IF @conversionErrorCount = 2 SET @targetType = 'nvarchar(MAX)';

		PRINT N'WARNING: Converting columns ' + @transformOutputColumnNames + N' to data-type [' + @targetType + N'] to account for CONVERT problems with @TransformOutput = 1;';
		SET @typeConversionAlter = REPLACE(@transformOutputAlterTemplate, N'{newType}', @targetType);
		EXEC sys.[sp_executesql] 
			@typeConversionAlter;

		UPDATE [#auditedTableColumns] 
		SET 
			[data_type] = @targetType 
		WHERE 
			[name] IN (SELECT [result] FROM dda.[split_string](REPLACE(REPLACE(@transformOutputColumnNames, N'[', N''), N']', N''), N',', 1));

		SET @jsonMappingCols = N'';
		SELECT
			@jsonMappingCols = @jsonMappingCols + @newline + @tab + @tab + @tab + QUOTENAME([name]) + N' ' + [data_type] + @tab + N'N''$.' + [name] + N'.~loc~'','
		FROM 
			[#auditedTableColumns] 
		ORDER BY 
			[column_id];

		SET @jsonMappingCols = LEFT(@jsonMappingCols, LEN(@jsonMappingCols) - 1);
	END;
	
	/* Setup specific projections: */
	DECLARE @insertDeleteProjection nvarchar(MAX) = REPLACE(@dynamicProjectionSql, N'{operation}', N'''INSERT'', ''DELETE''');
	SET @insertDeleteProjection = REPLACE(@insertDeleteProjection, N'{level}', N'');

	DECLARE @updateBeforeProjection nvarchar(MAX) = REPLACE(@dynamicProjectionSql, N'{operation}', N'''UPDATE''');
	SET @updateBeforeProjection = REPLACE(@updateBeforeProjection, N'{level}', N'before');

	DECLARE @updateAfterProjection nvarchar(MAX)  = REPLACE(@dynamicProjectionSql, N'{operation}', N'''UPDATE''');
	SET @updateAfterProjection = REPLACE(@updateAfterProjection, N'{level}', N'after');

	SET @insertDeleteProjection = REPLACE(@insertDeleteProjection, N'{jsonMapping}', REPLACE(@jsonMappingCols, N'.~loc~', N''));
	SET @updateBeforeProjection = REPLACE(@updateBeforeProjection, N'{jsonMapping}', REPLACE(@jsonMappingCols, N'.~loc~', N'.from'));
	SET @updateAfterProjection = REPLACE(@updateAfterProjection, N'{jsonMapping}', REPLACE(@jsonMappingCols, N'.~loc~', N'.to'));

	BEGIN TRY
		EXEC sys.[sp_executesql]
			@insertDeleteProjection;

		EXEC sys.[sp_executesql]
			@updateBeforeProjection;

		EXEC sys.[sp_executesql]
			@updateAfterProjection;
	END TRY
	BEGIN CATCH 
		SELECT @errorID = ERROR_NUMBER(), @errorMessage = ERROR_MESSAGE();
		IF @errorID = 245 BEGIN 
			SET @conversionErrorCount = @conversionErrorCount + 1;
			IF @conversionErrorCount < 3 GOTO EXECUTE_PROJECTION;

			RAISERROR(N'Data-Conversion error due to @TransformOutput = 1. Please set @TransformOutput = 0 and retry.%s%sConversion Error 245: %s', 16, 1, @newline, @tab, @errorMessage);
			RETURN -110;
		END;

		RAISERROR(N'Error %s - %s', 16, 1, @errorID, @errorMessage);
	END CATCH;

	/* Add row-ids for both output types: */
	SELECT 
		ROW_NUMBER() OVER(ORDER BY [dda.audit_id], [dda.row_audit_id], [dda.level] DESC) [dda.row_id],
		CAST(ROW_NUMBER() OVER (PARTITION BY [dda.audit_id] ORDER BY [dda.audit_id], [dda.row_audit_id], [dda.level] DESC) AS sysname) [dda.row_marker],
		*
	INTO 
		[#final_projection]
	FROM 
		[#projection]
	ORDER BY 
		[dda.audit_id], [dda.row_audit_id], [dda.level] DESC;

	/* Now that we don't need to order by json_row_id (as part of the order by) ... give it a bit more context: */
	ALTER TABLE [#final_projection] ALTER COLUMN [dda.row_audit_id] sysname NOT NULL;
	UPDATE [#final_projection] 
	SET 
		[dda.row_audit_id] = CAST([dda.audit_id] AS sysname) + N'.' + [dda.row_audit_id] + CASE WHEN [dda.level] = N'' THEN N'' ELSE N'._' + [dda.level] END;

	ALTER TABLE [#final_projection] DROP COLUMN [dda.level];
	
	IF UPPER(@ViewType) = N'GRID' BEGIN 
		
		ALTER TABLE [#final_projection] DROP COLUMN [ =>];
		ALTER TABLE [#final_projection] DROP COLUMN [dda.row_marker];

		SELECT 
			* 
		FROM 
			[#final_projection]
		ORDER BY 
			[dda.row_id];
		
		RETURN 0;
	END;

	UPDATE [#final_projection] 
	SET 
		[dda.row_marker] = CASE WHEN [dda.row_marker] = N'1' THEN CAST([dda.audit_id] AS sysname) ELSE N'' END;

	DECLARE @finalProjection nvarchar(MAX) = N'SELECT 
		CASE WHEN [dda.row_marker] = [dda.audit_id] THEN [dda.row_marker] ELSE N'''' END [dda.audit_id],
		CASE WHEN [dda.row_marker] = [dda.audit_id] THEN CONVERT(sysname, [dda.timestamp], 121) ELSE N'''' END [dda.timestamp],
		CASE WHEN [dda.row_marker] = [dda.audit_id] THEN [dda.original_login] ELSE N'''' END [dda.original_login],
		CASE WHEN [dda.row_marker] = [dda.audit_id] THEN [dda.operation_type] ELSE N'''' END [dda.operation_type],
		CASE WHEN [dda.row_marker] = [dda.audit_id] THEN CAST([dda.row_count] AS sysname) ELSE N'''' END [dda.row_count],
		[dda.row_audit_id],
		[ =>], {keyCols}{dataCols}
	FROM 
		[#final_projection]
	ORDER BY 
		[dda.row_id]; ';

	SET @insertAndSelectColumns = LEFT(@insertAndSelectColumns, LEN(@insertAndSelectColumns) - 1);

	SET @finalProjection = REPLACE(@finalProjection, N'{keyCols}', REPLACE(@insertAndSelectKeyCols, N'[y].[', N'['));
	SET @finalProjection = REPLACE(@finalProjection, N'{dataCols}', REPLACE(@insertAndSelectColumns, N'[y].[', N'['));

	EXEC [admindb].dbo.[print_long_string] @finalProjection;
	


	EXEC sys.[sp_executesql] 
		@finalProjection;

	RETURN 0;
GO