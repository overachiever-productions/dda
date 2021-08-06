/*
	EXAMPLE Signatures:

			EXEC dda.[get_audit_data]
				@StartTime = '2021-01-01 18:55:05',
				@EndTime = '2021-01-30 18:55:05',
				@TransformOutput = 1,
				@FromIndex = 1, 
				@ToIndex = 20;

			EXEC dda.[get_audit_data]
				@TargetUsers = N'sa, bilbo',
				--@TargetTables = N'SortTable,Errors',
				@TransformOutput = 1,
				@FromIndex = 20,
				@ToIndex = 40;


		-- AuditID Specific Searches: 
			EXEC dda.[get_audit_data]
				@StartAuditID = 1017;

			EXEC dda.[get_audit_data]
				@StartAuditID = 1017, 
				@EndAuditID = 1021;

		-- TransactionID Specific Searches:
			EXEC dda.[get_audit_data]
				@StartTransactionID = '2021-039-017406316';


			EXEC dda.[get_audit_data]
				@StartTransactionID = '2021-039-017406316', 
				@EndTransactionID = '2021-039-017633755';



*/

DROP PROC IF EXISTS dda.[get_audit_data];
GO

--## NOTE: Conditional Build (i.e., defaults to SQL Server 2016 version (XML-concat vs STRING_AGG()), but ALTERs to STRING_CONCAT on 2017+ instances).

CREATE PROC dda.[get_audit_data]
	@StartTime					datetime		= NULL, 
	@EndTime					datetime		= NULL, 
	@TargetUsers				nvarchar(MAX)	= NULL, 
	@TargetTables				nvarchar(MAX)	= NULL, 
	@StartAuditID				int				= NULL,
	@EndAuditID					int				= NULL,
	@StartTransactionID			sysname			= NULL, 
	@EndTransactionID			sysname			= NULL,
	@TransactionDate			date			= NULL,
	@TransformOutput			bit				= 1,
	@FromIndex					int				= 1, 
	@ToIndex					int				= 100
AS
    SET NOCOUNT ON;
	
	-- {copyright}

	SET @TargetUsers = NULLIF(@TargetUsers, N'');
	SET @TargetTables = NULLIF(@TargetTables, N'');		
	SET @TransformOutput = ISNULL(@TransformOutput, 1);

	SET @StartTransactionID = NULLIF(@StartTransactionID, N'');
	SET @EndTransactionID = NULLIF(@EndTransactionID, N'');

	SET @FromIndex = ISNULL(@FromIndex, 1);
	SET @ToIndex = ISNULL(@ToIndex, 1);

	IF @StartTime IS NOT NULL AND @EndTime IS NULL BEGIN 
		SET @EndTime = DATEADD(MINUTE, 2, GETDATE());
	END;

	IF @EndTime IS NOT NULL AND @StartTime IS NULL BEGIN 
		RAISERROR(N'@StartTime MUST be specified if @EndTime is specified. (@StartTime can be specified without @EndTime - and @EndTime will be set to GETDATE().)', 16, 1);
		RETURN - 10;
	END;

	IF (@StartTime IS NULL AND @EndTime IS NULL) AND (@StartAuditID IS NULL) AND (@StartTransactionID IS NULL) BEGIN
		IF @TargetUsers IS NULL AND @TargetTables IS NULL BEGIN 
			RAISERROR(N'Queries against Audit data MUST be constrained - either @StartTime [+ @EndTIme], or @TargetUsers, or @TargetTables or @StartAuditID/@StartTransactionIDs - or a combination of time, table, and user constraints.', 16, 1);
			RETURN -11;
		END;
	END;

	IF @StartTime IS NOT NULL BEGIN 
		IF @StartTime > @EndTime BEGIN
			RAISERROR(N'@StartTime may not be > @EndTime - please check inputs and try again.', 16, 1);
			RETURN -12;
		END;
	END;

	IF @EndAuditID IS NOT NULL AND (@StartAuditID IS NULL OR @EndAuditID <= @StartAuditID) BEGIN 
		RAISERROR(N'@EndAuditID can only be specified when @StartAuditID has been specified and when @EndAuditID is > @StartAuditID. If you wish to specify just a single AuditID only, use @StartAuditID only.', 16, 1);
		RETURN -13;
	END;

	IF @EndTransactionID IS NOT NULL AND @StartTransactionID IS NULL BEGIN 
		RAISERROR(N'@EndTransactionID can only be used when @StartTransactionID has been specified. If you wish to specify just a single TransactionID only, use @StartTransactionID only.', 16, 1);
		RETURN -14;
	END;

	-- Grab matching rows based upon inputs/constraints:
	DECLARE @coreQuery nvarchar(MAX) = N'WITH total AS (
	SELECT 
		ROW_NUMBER() OVER (ORDER BY [timestamp]) [row_number],
		[audit_id]
	FROM 
		[dda].[audits]
	WHERE 
		{TimeFilters}{Users}{Tables}{AuditID}{TransactionID}
) 
SELECT @coreJSON = (SELECT 
	[row_number],
	(SELECT COUNT(*) FROM [total]) [total_rows],
	[audit_id]
FROM 
	total 
WHERE 
	[total].[row_number] >= @FromIndex AND [total].[row_number] <= @ToIndex
FOR JSON PATH);
';

	DECLARE @timeFilters nvarchar(MAX) = N'';
	DECLARE @users nvarchar(MAX) = N'';
	DECLARE @tables nvarchar(MAX) = N'';
	DECLARE @auditIdClause nvarchar(MAX) = N'';
	DECLARE @transactionIdClause nvarchar(MAX) = N'';
	DECLARE @predicated bit = 0;
	DECLARE @newlineAndTabs sysname = N'
		'; 

	IF @StartTime IS NOT NULL BEGIN 
		SET @timeFilters = N'[timestamp] >= ''' + CONVERT(sysname, @StartTime, 121) + N''' AND [timestamp] <= ''' + CONVERT(sysname, @EndTime, 121) + N''' '; 
		SET @predicated = 1;
	END;

	IF @TargetUsers IS NOT NULL BEGIN 
		IF @TargetUsers LIKE N'%,%' BEGIN 
			SET @users  = N'[user] IN (';

			SELECT 
				@users = @users + N'''' + [result] + N''', '
			FROM 
				dda.[split_string](@TargetUsers, N',', 1)
			ORDER BY 
				[row_id];

			SET @users = LEFT(@users, LEN(@users) - 1) + N') ';

		  END;
		ELSE BEGIN 
			SET @users = N'[user] = ''' + @TargetUsers + N''' ';
		END;
		
		IF @predicated = 1 SET @users = @newlineAndTabs + N'AND ' + @users;
		SET @predicated = 1;
	END;

	IF @TargetTables IS NOT NULL BEGIN
		IF @TargetTables LIKE N'%,%' BEGIN 
			SET @tables = N'[table] IN (';

			SELECT
				@tables = @tables + N'''' + [result] + N''', '
			FROM 
				dda.[split_string](@TargetTables, N',', 1)
			ORDER BY 
				[row_id];

			SET @tables = LEFT(@tables, LEN(@tables) -1) + N') ';

		  END;
		ELSE BEGIN 
			SET @tables = N'[table] = ''' + @TargetTables +''' ';  
		END;
		
		IF @predicated = 1 SET @tables = @newlineAndTabs + N'AND ' + @tables;
		SET @predicated = 1;
	END;
	
	IF @StartAuditID IS NOT NULL BEGIN 
		IF @EndAuditID IS NULL BEGIN
			SET @auditIdClause = N'[audit_id] = ' + CAST(@StartAuditID AS sysname);
		  END;
		ELSE BEGIN 
			SET @auditIdClause = N'[audit_id] >= ' + CAST(@StartAuditID AS sysname) + N' AND [audit_id] <= '  + CAST(@EndAuditID AS sysname)
		END;

		IF @predicated = 1 SET @auditIdClause = @newlineAndTabs + N'AND ' + @auditIdClause;
		SET @predicated = 1;
	END;

	IF @StartTransactionID IS NOT NULL BEGIN 
		DECLARE @year int, @doy int;
		DECLARE @txDate datetime; 
		DECLARE @startTx int;
		DECLARE @endTx int;
		
		IF @StartTransactionID LIKE N'%-%' BEGIN 
			SELECT @year = LEFT(@StartTransactionID, 4);
			SELECT @doy = SUBSTRING(@StartTransactionID, 6, 3);
			SET @startTx = TRY_CAST((SELECT [result] FROM dda.[split_string](@StartTransactionID, N'-', 1) WHERE [row_id] = 3) AS int);

			SET @txDate = CAST(CAST(@year AS sysname) + N'-01-01' AS datetime);
			SET @txDate = DATEADD(DAY, @doy - 1, @txDate);
		  END;
		ELSE BEGIN 
			IF @TransactionDate IS NOT NULL SET @txDate = @TransactionDate;
			SET @startTx = TRY_CAST(@StartTransactionID AS int);
		END;

		IF @EndTransactionID IS NOT NULL BEGIN 
			IF @EndTransactionID LIKE N'%-%' BEGIN 
				SET @endTx = TRY_CAST((SELECT [result] FROM dda.[split_string](@EndTransactionID, N'-', 1) WHERE [row_id] = 3) AS int);
			  END; 
			ELSE BEGIN 
				SET @endTx = TRY_CAST(@EndTransactionID AS int);
			END;

			SET @transactionIdClause = N'([transaction_id] >= ' + CAST(@startTx AS sysname) + N' AND [transaction_id] <= ' + CAST(@endTx AS sysname);
		  END;
		ELSE BEGIN 
			SET @transactionIdClause = N'([transaction_id] = ' + CAST(@startTx AS sysname);
		END;

		IF @startTx IS NULL BEGIN 
			RAISERROR(N'Invalid @StartTransaction Specified. Specify either the exact (integer) ID from dda.audits.transaction_id OR a formatted dddd-doy-####### value as provided by dda.get_audit_data.', 16, 1);
			RETURN -80;
		END;

		IF @txDate IS NULL BEGIN 
			RAISERROR(N'Invalid @StartTransaction Specified. Specify either the exact (integer) ID from dda.audits.transaction_id OR a formatted dddd-doy-####### value as provided by dda.get_audit_data.', 16, 1);
			RETURN -81;
		  END;
		ELSE BEGIN 
			SET @transactionIdClause = @transactionIdClause + N' AND [timestamp] >= ''' + CONVERT(sysname, @txDate, 121) + N''' AND [timestamp] < ''' + CONVERT(sysname, DATEADD(DAY, 1, @txDate), 121) + N'''';
		END;
		
		SET @transactionIdClause = @transactionIdClause + N')';

		IF @predicated = 1 SET @transactionIdClause = @newlineAndTabs + N'AND ' + @transactionIdClause;
		SET @predicated = 1;
	END;

	SET @coreQuery = REPLACE(@coreQuery, N'{TimeFilters}', @timeFilters);
	SET @coreQuery = REPLACE(@coreQuery, N'{Users}', @users);
	SET @coreQuery = REPLACE(@coreQuery, N'{Tables}', @tables);
	SET @coreQuery = REPLACE(@coreQuery, N'{AuditID}', @auditIdClause);
	SET @coreQuery = REPLACE(@coreQuery, N'{TransactionID}', @transactionIdClause);
	
	DECLARE @coreJSON nvarchar(MAX);
	EXEC sp_executesql 
		@coreQuery, 
		N'@FromIndex int, @ToIndex int, @coreJSON nvarchar(MAX) OUTPUT', 
		@FromIndex = @FromIndex, 
		@ToIndex = @ToIndex, 
		@coreJSON = @coreJSON OUTPUT;

	DECLARE @matchedRows int;
	CREATE TABLE #raw_data ( 
		[row_number] int NOT NULL,
		[total_rows] int NOT NULL, 
		[audit_id] int NOT NULL,
		[timestamp] datetime NOT NULL,
		[table] sysname NOT NULL,
		[translated_table] sysname NULL,
		[user] sysname NOT NULL,
		[operation_type] char(6) NOT NULL,
		[transaction_id] int NOT NULL,
		[row_count] int NOT NULL,
		[change_details] nvarchar(max) NULL, 
		[translated_json] nvarchar(MAX) NULL
	);

	INSERT INTO [#raw_data] (
		[x].[row_number],
		[x].[total_rows],
		[x].[audit_id],
		[a].[timestamp],
		[a].[table],
		[a].[user],
		[a].[operation_type],
		[a].[transaction_id],
		[a].[row_count],
		[a].[change_details]
	)
	SELECT 
		[x].[row_number],
		[x].[total_rows],
		[x].[audit_id],
		[a].[timestamp],
		[a].[schema] + N'.' + [a].[table] [table],
		[a].[user],
		[a].[operation],
		[a].[transaction_id],
		[a].[row_count],
		[a].[audit] [change_details]
	FROM 
		OPENJSON(@coreJSON) WITH ([row_number] int, [total_rows] int, [audit_id] int) [x]
		INNER JOIN dda.[audits] [a] ON [x].[audit_id] = [a].[audit_id];

	SELECT @matchedRows = @@ROWCOUNT;

	/* Short-circuit options for transforms: */
	IF (@matchedRows < 1) OR (@TransformOutput <> 1) GOTO Final_Projection;

	/* Translate table-names: */
	UPDATE x 
	SET 
		[x].[translated_table] = CASE WHEN t.[translated_name] IS NULL THEN x.[table] ELSE t.[translated_name] END
	FROM 
		[#raw_data] x 
		LEFT OUTER JOIN [dda].[translation_tables] t ON x.[table] = t.[table_name];

	CREATE TABLE #scalar ( 
		[scalar_id] int IDENTITY(1,1) NOT NULL, 
		[audit_id] int NOT NULL, 
		[operation_type] char(6) NOT NULL,
		[row_count] int NOT NULL,
		[row_number] int NOT NULL, 
		[json_row_id] int NOT NULL, 
		[source_table] sysname NOT NULL, 
		[change_details] nvarchar(MAX) NOT NULL, 
		[translate_keys] nvarchar(MAX) NULL, 
		[translated_details] nvarchar(MAX) NULL
	);

	WITH distinct_json_rows AS ( 
		SELECT 
			[x].[audit_id],
			[x].[operation_type],
			[x].[row_count],
			[x].[row_number], 
			[r].[Key] [json_row_id], 
			[x].[table], 
			N'[' + [r].[Value] + N']' [change_details]  /* NOTE: without [surrounding brackets], shred no-worky down below... */
		FROM 
			[#raw_data] x 
			CROSS APPLY OPENJSON(JSON_QUERY([x].[change_details], N'$')) r 
		WHERE 
			[x].[row_count] > 1
	) 

	INSERT INTO [#scalar] (
		[audit_id],
		[operation_type],
		[row_count],
		[row_number],
		[json_row_id],
		[source_table],
		[change_details]
	)
	SELECT 
		[audit_id],
		[operation_type],
		[row_count],
		[row_number],
		[json_row_id],
		[table],
		[change_details]
	FROM 
		[distinct_json_rows]

	INSERT INTO [#scalar] (
		[audit_id],
		[operation_type],
		[row_count],
		[row_number],
		[json_row_id],
		[source_table],
		[change_details]
	)
	SELECT 
		[audit_id],
		[operation_type],
		1 [row_count], 
		[row_number],
		0 [json_row_id],
		[table],
		[change_details]
	FROM 
		[#raw_data]
	WHERE
		[row_count] = 1;

	CREATE TABLE [#nodes] ( 
		[node_id] int IDENTITY(1,1) NOT NULL, 
		[audit_id] int NOT NULL,
		[operation_type] char(6) NOT NULL,
		[row_number] int NOT NULL, 
		[json_row_id] int NOT NULL,
		[node_type] sysname NOT NULL,
		[source_table] sysname NOT NULL, 
		[parent_json] nvarchar(MAX) NOT NULL,
		[current_json] nvarchar(MAX) NULL,
		[original_column] sysname NOT NULL, 
		[original_value] nvarchar(MAX) NULL, 
		[original_value_type] int NOT NULL, 
		[translated_value] nvarchar(MAX) NULL, 
		[translated_column] sysname NULL, 
		[translated_value_type] int NULL 
	);

	WITH [keys] AS ( 
		SELECT 
			[x].[audit_id],
			[x].[operation_type],
			[x].[row_number],
			[x].[json_row_id],
			N'key' [node_type],
			[x].[source_table],
			[x].[change_details] [parent_json],
			[z].[Value] [current_json],
			[y].[Key] [original_column],
			ISNULL([y].[Value], N'null') [original_value],
			[y].[Type] [original_value_type]
		FROM 
			[#scalar] x 
			OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], N'$[0].key'), N'$') z 
			CROSS APPLY OPENJSON([z].[Value], N'$') y
	)

	INSERT INTO [#nodes] (
		[audit_id],
		[operation_type],
		[row_number],
		[json_row_id],
		[node_type],
		[source_table],
		[parent_json],
		[current_json],
		[original_column],
		[original_value],
		[original_value_type]
	)
	SELECT 
		[audit_id],
		[operation_type],
		[row_number],
		[json_row_id],
		[node_type],
		[source_table],
		[parent_json],
		[current_json],
		[original_column],
		[original_value],
		[original_value_type] 
	FROM 
		[keys];
	
	WITH [details] AS ( 
		SELECT 
			[x].[audit_id],
			[x].[operation_type],
			[x].[row_number],
			[x].[json_row_id],
			N'detail' [node_type],
			[x].[source_table],
			[x].[change_details] [parent_json],
			[z].[Value] [current_json],
			[y].[Key] [original_column],
			ISNULL([y].[Value], N'null') [original_value],
			[y].[Type] [original_value_type]
		FROM 
			[#scalar] x 
			OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], N'$[0].detail'), N'$') z 
			CROSS APPLY OPENJSON([z].[Value], N'$') y
		WHERE 
			[y].[Value] NOT LIKE '%from":%"to":%'
	) 

	INSERT INTO [#nodes] (
		[audit_id],
		[operation_type],
		[row_number],
		[json_row_id],
		[node_type],
		[source_table],
		[parent_json],
		[current_json],
		[original_column],
		[original_value],
		[original_value_type]
	)
	SELECT 
		[audit_id],
		[operation_type],
		[row_number],
		[json_row_id],
		[node_type],
		[source_table],
		[parent_json],
		[current_json],
		[original_column],
		[original_value],
		[original_value_type] 
	FROM 
		[details];

	/* Extract from/to child nodes for UPDATES: */
	SELECT 
		[x].[audit_id],
		[x].[operation_type],
		[x].[row_number],
		[x].[json_row_id],
		N'detail' [node_type],
		[x].[source_table],
		[x].[change_details] [parent_json],
		[z].[Value] [current_json],
		[y].[Key] [original_column],
		ISNULL([y].[Value], N'null') [original_value],
		[y].[Type] [original_value_type]
	INTO 
		#updates
	FROM 
		[#scalar] x 
		OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], N'$[0].detail'), N'$') z 
		CROSS APPLY OPENJSON([z].[Value], N'$') y
	WHERE 
		[y].[Type] = 5 AND
		[y].[Value] LIKE '%from":%"to":%'
	OPTION (MAXDOP 1);

	WITH [from_to] AS ( 

		SELECT 
			[x].[audit_id],
			[x].[operation_type],
			[x].[row_number],
			[x].[json_row_id],
			[y].[Key] [node_type],
			[x].[source_table],
			[x].[parent_json],
			[x].[current_json],
			[x].[original_column],
			ISNULL([y].[Value], N'null') [original_value], 
			[y].[Type] [original_value_type]
		FROM 
			[#updates] x
			CROSS APPLY OPENJSON([x].[original_value], N'$') y
	)

	INSERT INTO [#nodes] (
		[audit_id],
		[operation_type],
		[row_number],
		[json_row_id],
		[node_type],
		[source_table],
		[parent_json],
		[current_json],
		[original_column],
		[original_value],
		[original_value_type]
	)
	SELECT 
		[audit_id],
		[operation_type],
		[row_number],
		[json_row_id],
		[node_type],
		[source_table],
		[parent_json],
		[current_json],
		[original_column],
		[original_value],
		[original_value_type] 
	FROM 
		[from_to];	
	
	/* Translate Column Names: */
	UPDATE x 
	SET 
		x.[translated_column] = [c].[translated_name]
	FROM 
		[#nodes] x 
		LEFT OUTER JOIN dda.[translation_columns] c ON [x].[source_table] COLLATE SQL_Latin1_General_CP1_CI_AS = [c].[table_name] AND [x].[original_column] COLLATE SQL_Latin1_General_CP1_CI_AS = [c].[column_name]
	WHERE 
		x.[translated_column] IS NULL; 


	CREATE TABLE #translation_key_values (
		[row_id] int IDENTITY(1,1) NOT NULL, 
		[source_table] sysname NOT NULL, 
		[source_column] sysname NOT NULL, 
		[translation_key] nvarchar(MAX) NOT NULL, 
		[translation_value] nvarchar(MAX) NOT NULL, 
		[target_json_type] tinyint NULL,
		[weight] int NOT NULL DEFAULT (1)
	);	

	IF EXISTS (SELECT NULL FROM [#nodes] n LEFT OUTER JOIN dda.[translation_keys] tk ON [n].[source_table] = [tk].[table_name] AND [n].[original_column] = [tk].[column_name] WHERE [tk].[table_name] IS NOT NULL) BEGIN 

		DECLARE @sourceTable sysname, @sourceColumn sysname, @translationTable sysname, @translationKey nvarchar(MAX), @translationValue nvarchar(MAX);
		DECLARE @translationSql nvarchar(MAX);

		DECLARE [translator] CURSOR LOCAL FAST_FORWARD FOR 
		SELECT DISTINCT
			[tk].[table_name], 
			[tk].[column_name], 
			[tk].[key_table],
			[tk].[key_column], 
			[tk].[value_column]
		FROM 
			dda.[translation_keys] tk	
			LEFT OUTER JOIN [#nodes] x ON [tk].[table_name] = [x].[source_table] AND [tk].[column_name] = [x].[original_column]
		WHERE 
			[x].[source_table] IS NOT NULL AND [x].[original_column] IS NOT NULL;
				
		OPEN [translator];
		FETCH NEXT FROM [translator] INTO @sourceTable, @sourceColumn, @translationTable, @translationKey, @translationValue;
		
		WHILE @@FETCH_STATUS = 0 BEGIN
		
			SET @translationSql = N'INSERT INTO #translation_key_values ([source_table], [source_column], [translation_key], [translation_value]) 
				SELECT @sourceTable [source_table], @sourceColumn [source_column], ' + QUOTENAME(@translationKey) + N' [translation_key], ' + QUOTENAME(@translationValue) + N' [translation_value] 
				FROM 
					' + @translationTable + N';'

			EXEC sp_executesql 
				@translationSql, 
				N'@sourceTable sysname, @sourceColumn sysname', 
				@sourceTable = @sourceTable, 
				@sourceColumn = @sourceColumn;			

			FETCH NEXT FROM [translator] INTO @sourceTable, @sourceColumn, @translationTable, @translationKey, @translationValue;
		END;
		
		CLOSE [translator];
		DEALLOCATE [translator];

	END;

	INSERT INTO [#translation_key_values] (
		[source_table],
		[source_column],
		[translation_key],
		[translation_value], 
		[target_json_type],
		[weight]
	)
	SELECT DISTINCT /*  TODO: tired... not sure why I'm tolerating this code-smell/nastiness - but need to address it... */
		v.[table_name] [source_table], 
		v.[column_name] [source_column], 
		v.[key_value] [translation_key],
		v.[translation_value], 
		v.[target_json_type],
		2 [weight]
	FROM 
		[#nodes] x 
		INNER JOIN [dda].[translation_values] v ON x.[source_table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[original_column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name];

	/* Explicit values in dda.translation_values can/will/should OVERWRITE any mappings or translations provided by FKs defined in dda.translation_keys - so remove lower-ranked duplicates: */
	WITH duplicates AS ( 
		SELECT
			row_id
		FROM 
			[#translation_key_values] t1 
			WHERE EXISTS ( 
				SELECT NULL 
				FROM [#translation_key_values] t2 
				WHERE 
					t1.[source_table] = t2.[source_table]
					AND t1.[source_column] = t2.[source_column]
					AND t1.[translation_key] = t2.[translation_key]
				GROUP BY 
					t2.[source_table], t2.[source_column], t2.[translation_key]
				HAVING 
					COUNT(*) > 1 
					AND MAX(t2.[weight]) > t1.[weight]
			)
	)

	DELETE x 
	FROM 
		[#translation_key_values] x 
		INNER JOIN [duplicates] d ON [x].[row_id] = [d].[row_id];

	IF EXISTS (SELECT NULL FROM [#translation_key_values]) BEGIN 
		UPDATE x 
		SET 
			x.[translated_value] = v.[translation_value], 
			x.[translated_value_type] = CASE WHEN v.[target_json_type] IS NOT NULL THEN [v].[target_json_type] ELSE dda.[get_json_data_type](v.[translation_value]) END
		FROM 
			[#nodes] x 
			INNER JOIN [#translation_key_values] v ON 
				[x].[source_table] COLLATE SQL_Latin1_General_CP1_CI_AS = [v].[source_table] 
				AND x.[original_column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_column] 
				AND x.[original_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[translation_key];
	END;

	/* RE-ASSEMBLY */

	/* Start with from-to values and translations: */
	SELECT 
		ISNULL([translated_column], [original_column]) [column_name], 
		LEAD(ISNULL([translated_column], [original_column]), 1, NULL) OVER(PARTITION BY [row_number], [json_row_id] ORDER BY [node_id]) [next_column_name],
		[row_number], 
		[json_row_id], 
		[node_type],
		ISNULL([translated_value], [original_value]) [value], 
		ISNULL([translated_value_type], [original_value_type]) [value_type], 
		[node_id]
	INTO 
		#parts
	FROM 
		[#nodes]
	WHERE 
		[node_type] IN (N'from', N'to');

	WITH [froms] AS ( 
		SELECT 
			[x].[column_name],
			[x].[row_number],
			[x].[json_row_id],
			CASE WHEN [x].[value_type] = 1 THEN STRING_ESCAPE([x].[value], 'json') ELSE [x].[value] END [value], 
			[x].[value_type],
			[x].[node_id] 
		FROM 
			[#parts] x
		WHERE 
			[node_type] = N'from'
	), 
	[tos] AS ( 
		SELECT 
			[x].[column_name],
			[x].[row_number],
			[x].[json_row_id],
			CASE WHEN [x].[value_type] = 1 THEN STRING_ESCAPE([x].[value], 'json') ELSE [x].[value] END [value],
			[x].[value_type]
		FROM 
			froms f 
			INNER JOIN [#parts] x ON f.[node_id] + 1 = x.[node_id]
	), 
	[flattened] AS ( 

		SELECT 
			[f].[row_number],
			[f].[json_row_id],
			[f].[node_id],
			N'"' + [f].[column_name] + N'":{"from":' + CASE WHEN [f].[value_type] = 1 THEN N'"' + [f].[value] + N'"' ELSE [f].[value] END + ',"to":' + CASE WHEN [t].[value_type] = 1 THEN N'"' + [t].[value] + N'"' ELSE [t].[value] END + N'}' [collapsed]
		FROM 
			[froms] f 
			INNER JOIN [tos] t ON f.[row_number] = t.[row_number] AND f.[json_row_id] = t.[json_row_id] AND f.[column_name] = t.[column_name]
	), 
	[aggregated] AS ( 
		SELECT 
			x.[row_number],
			x.[json_row_id],
			N'{' +
				NULLIF(COALESCE(STUFF((SELECT N',' + f2.[collapsed] FROM [flattened] f2 WHERE [f2].[row_number] = x.[row_number] AND f2.[json_row_id] = x.[json_row_id] ORDER BY [f2].[row_number], [f2].[json_row_id], [f2].[node_id] FOR XML PATH(''), TYPE).value(N'.[1]', N'nvarchar(MAX)'), 1, 1, N''), N''), N'') + 
			N'}' [detail]
		FROM 
			[flattened] x
		GROUP BY 
			x.[row_number], x.[json_row_id]
	)

	UPDATE x 
	SET 
		[x].[translated_details] = a.[detail]
	FROM 
		[#scalar] x 
		INNER JOIN [aggregated] a ON x.[row_number] = a.[row_number] AND x.[json_row_id] = a.[json_row_id];

	/* Re-encode de-encoded (or non-encoded (translation)) JSON: */
	UPDATE [#nodes] 
	SET 
		[original_value] = CASE WHEN [original_value_type] = 1 THEN STRING_ESCAPE([original_value], 'json') ELSE [original_value] END, 
		[translated_value] = CASE WHEN [translated_value_type] = 1 THEN STRING_ESCAPE([translated_value], 'json') ELSE [translated_value] END
	WHERE 
		ISNULL([translated_value_type], [original_value_type]) = 1; 

	/* Serialize Details (for non UPDATEs - they've already been handled above) */
	WITH [flattened] AS ( 
		SELECT 
			[row_number], 
			[json_row_id], 
			[node_id],
			N'"' + ISNULL([translated_column], [original_column]) + N'":' + CASE WHEN ISNULL([translated_value_type], [original_value_type]) = 1 THEN N'"' + ISNULL([translated_value], [original_value]) + N'"' ELSE ISNULL([translated_value], [original_value]) END [collapsed]
		FROM 
			[#nodes] 
		WHERE 
			[node_type] = N'detail'
	), 
	[aggregated] AS ( 
		SELECT 
			x.[row_number],
			x.[json_row_id], 
			N'{' + 
				NULLIF(COALESCE(STUFF((SELECT N',' + f2.[collapsed] FROM [flattened] f2 WHERE [f2].[row_number] = x.[row_number] AND f2.[json_row_id] = x.[json_row_id] ORDER BY [f2].[row_number], [f2].[json_row_id], [f2].[node_id] FOR XML PATH(''), TYPE).value(N'.[1]', N'nvarchar(MAX)'), 1, 1, N''), N''), N'') + 
			N'}' [detail]
		FROM 
			[flattened] x
		GROUP BY 
			x.[row_number],
			x.[json_row_id]
	)

	UPDATE x 
	SET 
		[x].[translated_details] = a.[detail]
	FROM 
		[#scalar] x 
		INNER JOIN [aggregated] a ON x.[row_number] = a.[row_number] AND x.[json_row_id] = a.[json_row_id]
	WHERE 
		x.[translated_details] IS NULL;

	/* Serialized Keys */
	WITH [flattened] AS (  
		SELECT 
			[row_number], 
			[json_row_id], 
			[node_id],
			N'"' + ISNULL([translated_column], [original_column]) + N'":' + CASE WHEN ISNULL([translated_value_type], [original_value_type]) = 1 THEN N'"' + ISNULL([translated_value], [original_value]) + N'"' ELSE ISNULL([translated_value], [original_value]) END [collapsed]
		FROM 
			[#nodes] 
		WHERE 
			[node_type] = N'key'
	),
	[aggregated] AS ( 
		SELECT 
			x.[row_number],
			x.[json_row_id], 
			N'{' + 
				--STRING_AGG([collapsed], N',') WITHIN GROUP (ORDER BY [row_number], [json_row_id], [node_id]) +
				NULLIF(COALESCE(STUFF((SELECT N',' + f2.[collapsed] FROM [flattened] f2 WHERE [f2].[row_number] = x.[row_number] AND [f2].[json_row_id] = [x].[json_row_id] ORDER BY [f2].[row_number], [f2].[json_row_id], [f2].[node_id] FOR XML PATH(''), TYPE).value(N'.[1]', N'nvarchar(MAX)'), 1, 1, N''), N''), N'') + 
			N'}' [keys]
		FROM 
			[flattened] x
		GROUP BY 
			x.[row_number],
			x.[json_row_id]			
	)

	UPDATE x 
	SET 
		x.[translate_keys] = a.[keys]
	FROM 
		[#scalar] x 
		INNER JOIN [aggregated] a ON x.[row_number] = a.[row_number] AND x.[json_row_id] = a.[json_row_id];

	/* MAP translated JSON back to #raw_data - starting with scalar rows, then move to multi-row JSON ... */
	UPDATE x 
	SET 
	 	x.[translated_json] = N'[{"key":[' + s.[translate_keys] + N'],"detail":[' + s.[translated_details] + N']}]'
	FROM 
		[#raw_data] x 
		INNER JOIN [#scalar] s ON [x].[row_number] = [s].[row_number]
	WHERE 
		x.[row_count] = 1;

	WITH [flattened] AS ( 
		SELECT 
			x.[row_number], 
			N'[' +
				NULLIF(COALESCE(STUFF((SELECT N',{"key":[' + x2.[translate_keys] + N'],"detail":[' + x2.[translated_details] + N']}' FROM [#scalar] x2 WHERE x.[row_number] = x2.[row_number] ORDER BY [x2].[row_number], [x2].[json_row_id] FOR XML PATH(''), TYPE).value(N'.[1]', N'nvarchar(MAX)'), 1, 1, N''), N''), N'') + 
			N']' [collapsed]
		FROM 
			[#scalar] x
		WHERE 
			x.[row_count] > 1
		GROUP BY 
			x.[row_number]
	) 

	UPDATE x 
	SET 
		x.[translated_json] = f.[collapsed]
	FROM 
		[#raw_data] x 
		INNER JOIN [flattened] f ON [x].[row_number] = [f].[row_number] 
	WHERE 
		x.[translated_json] IS NULL;

Final_Projection: 
	SELECT 
		[row_number],
		[total_rows],
		[audit_id],
		[timestamp],
		[user],
		ISNULL([translated_table], [table]) [table],
		CONCAT(DATEPART(YEAR, [timestamp]), N'-', RIGHT(N'000' + DATENAME(DAYOFYEAR, [timestamp]), 3), N'-', RIGHT(N'000000000' + CAST([transaction_id] AS sysname), 9)) [transaction_id],
		[operation_type],
		[row_count],
		CASE WHEN [translated_json] IS NULL AND [change_details] LIKE N'%,"dump":%' THEN [change_details] ELSE ISNULL([translated_json], [change_details]) END [change_details] 
	FROM 
		[#raw_data]
	ORDER BY 
		[row_number];

	RETURN 0;
GO

--##CONDITIONAL_VERSION(> 14.0) 

ALTER PROC dda.[get_audit_data]
	@StartTime					datetime		= NULL, 
	@EndTime					datetime		= NULL, 
	@TargetUsers				nvarchar(MAX)	= NULL, 
	@TargetTables				nvarchar(MAX)	= NULL, 
	@StartAuditID				int				= NULL,
	@EndAuditID					int				= NULL,
	@StartTransactionID			sysname			= NULL, 
	@EndTransactionID			sysname			= NULL,
	@TransactionDate			date			= NULL,
	@TransformOutput			bit				= 1,
	@FromIndex					int				= 1, 
	@ToIndex					int				= 100
AS
    SET NOCOUNT ON;
	
	-- {copyright}

	SET @TargetUsers = NULLIF(@TargetUsers, N'');
	SET @TargetTables = NULLIF(@TargetTables, N'');		
	SET @TransformOutput = ISNULL(@TransformOutput, 1);

	SET @StartTransactionID = NULLIF(@StartTransactionID, N'');
	SET @EndTransactionID = NULLIF(@EndTransactionID, N'');

	SET @FromIndex = ISNULL(@FromIndex, 1);
	SET @ToIndex = ISNULL(@ToIndex, 1);

	IF @StartTime IS NOT NULL AND @EndTime IS NULL BEGIN 
		SET @EndTime = DATEADD(MINUTE, 2, GETDATE());
	END;

	IF @EndTime IS NOT NULL AND @StartTime IS NULL BEGIN 
		RAISERROR(N'@StartTime MUST be specified if @EndTime is specified. (@StartTime can be specified without @EndTime - and @EndTime will be set to GETDATE().)', 16, 1);
		RETURN - 10;
	END;

	IF (@StartTime IS NULL AND @EndTime IS NULL) AND (@StartAuditID IS NULL) AND (@StartTransactionID IS NULL) BEGIN
		IF @TargetUsers IS NULL AND @TargetTables IS NULL BEGIN 
			RAISERROR(N'Queries against Audit data MUST be constrained - either @StartTime [+ @EndTIme], or @TargetUsers, or @TargetTables or @StartAuditID/@StartTransactionIDs - or a combination of time, table, and user constraints.', 16, 1);
			RETURN -11;
		END;
	END;

	IF @StartTime IS NOT NULL BEGIN 
		IF @StartTime > @EndTime BEGIN
			RAISERROR(N'@StartTime may not be > @EndTime - please check inputs and try again.', 16, 1);
			RETURN -12;
		END;
	END;

	IF @EndAuditID IS NOT NULL AND (@StartAuditID IS NULL OR @EndAuditID <= @StartAuditID) BEGIN 
		RAISERROR(N'@EndAuditID can only be specified when @StartAuditID has been specified and when @EndAuditID is > @StartAuditID. If you wish to specify just a single AuditID only, use @StartAuditID only.', 16, 1);
		RETURN -13;
	END;

	IF @EndTransactionID IS NOT NULL AND @StartTransactionID IS NULL BEGIN 
		RAISERROR(N'@EndTransactionID can only be used when @StartTransactionID has been specified. If you wish to specify just a single TransactionID only, use @StartTransactionID only.', 16, 1);
		RETURN -14;
	END;

	-- Grab matching rows based upon inputs/constraints:
	DECLARE @coreQuery nvarchar(MAX) = N'WITH total AS (
	SELECT 
		ROW_NUMBER() OVER (ORDER BY [timestamp]) [row_number],
		[audit_id]
	FROM 
		[dda].[audits]
	WHERE 
		{TimeFilters}{Users}{Tables}{AuditID}{TransactionID}
) 
SELECT @coreJSON = (SELECT 
	[row_number],
	(SELECT COUNT(*) FROM [total]) [total_rows],
	[audit_id]
FROM 
	total 
WHERE 
	[total].[row_number] >= @FromIndex AND [total].[row_number] <= @ToIndex
FOR JSON PATH);
';

	DECLARE @timeFilters nvarchar(MAX) = N'';
	DECLARE @users nvarchar(MAX) = N'';
	DECLARE @tables nvarchar(MAX) = N'';
	DECLARE @auditIdClause nvarchar(MAX) = N'';
	DECLARE @transactionIdClause nvarchar(MAX) = N'';
	DECLARE @predicated bit = 0;
	DECLARE @newlineAndTabs sysname = N'
		'; 

	IF @StartTime IS NOT NULL BEGIN 
		SET @timeFilters = N'[timestamp] >= ''' + CONVERT(sysname, @StartTime, 121) + N''' AND [timestamp] <= ''' + CONVERT(sysname, @EndTime, 121) + N''' '; 
		SET @predicated = 1;
	END;

	IF @TargetUsers IS NOT NULL BEGIN 
		IF @TargetUsers LIKE N'%,%' BEGIN 
			SET @users  = N'[user] IN (';

			SELECT 
				@users = @users + N'''' + [result] + N''', '
			FROM 
				dda.[split_string](@TargetUsers, N',', 1)
			ORDER BY 
				[row_id];

			SET @users = LEFT(@users, LEN(@users) - 1) + N') ';

		  END;
		ELSE BEGIN 
			SET @users = N'[user] = ''' + @TargetUsers + N''' ';
		END;
		
		IF @predicated = 1 SET @users = @newlineAndTabs + N'AND ' + @users;
		SET @predicated = 1;
	END;

	IF @TargetTables IS NOT NULL BEGIN
		IF @TargetTables LIKE N'%,%' BEGIN 
			SET @tables = N'[table] IN (';

			SELECT
				@tables = @tables + N'''' + [result] + N''', '
			FROM 
				dda.[split_string](@TargetTables, N',', 1)
			ORDER BY 
				[row_id];

			SET @tables = LEFT(@tables, LEN(@tables) -1) + N') ';

		  END;
		ELSE BEGIN 
			SET @tables = N'[table] = ''' + @TargetTables +''' ';  
		END;
		
		IF @predicated = 1 SET @tables = @newlineAndTabs + N'AND ' + @tables;
		SET @predicated = 1;
	END;
	
	IF @StartAuditID IS NOT NULL BEGIN 
		IF @EndAuditID IS NULL BEGIN
			SET @auditIdClause = N'[audit_id] = ' + CAST(@StartAuditID AS sysname);
		  END;
		ELSE BEGIN 
			SET @auditIdClause = N'[audit_id] >= ' + CAST(@StartAuditID AS sysname) + N' AND [audit_id] <= '  + CAST(@EndAuditID AS sysname)
		END;

		IF @predicated = 1 SET @auditIdClause = @newlineAndTabs + N'AND ' + @auditIdClause;
		SET @predicated = 1;
	END;

	IF @StartTransactionID IS NOT NULL BEGIN 
		DECLARE @year int, @doy int;
		DECLARE @txDate datetime; 
		DECLARE @startTx int;
		DECLARE @endTx int;
		
		IF @StartTransactionID LIKE N'%-%' BEGIN 
			SELECT @year = LEFT(@StartTransactionID, 4);
			SELECT @doy = SUBSTRING(@StartTransactionID, 6, 3);
			SET @startTx = TRY_CAST((SELECT [result] FROM dda.[split_string](@StartTransactionID, N'-', 1) WHERE [row_id] = 3) AS int);

			SET @txDate = CAST(CAST(@year AS sysname) + N'-01-01' AS datetime);
			SET @txDate = DATEADD(DAY, @doy - 1, @txDate);
		  END;
		ELSE BEGIN 
			IF @TransactionDate IS NOT NULL SET @txDate = @TransactionDate;
			SET @startTx = TRY_CAST(@StartTransactionID AS int);
		END;

		IF @EndTransactionID IS NOT NULL BEGIN 
			IF @EndTransactionID LIKE N'%-%' BEGIN 
				SET @endTx = TRY_CAST((SELECT [result] FROM dda.[split_string](@EndTransactionID, N'-', 1) WHERE [row_id] = 3) AS int);
			  END; 
			ELSE BEGIN 
				SET @endTx = TRY_CAST(@EndTransactionID AS int);
			END;

			SET @transactionIdClause = N'([transaction_id] >= ' + CAST(@startTx AS sysname) + N' AND [transaction_id] <= ' + CAST(@endTx AS sysname);
		  END;
		ELSE BEGIN 
			SET @transactionIdClause = N'([transaction_id] = ' + CAST(@startTx AS sysname);
		END;

		IF @startTx IS NULL BEGIN 
			RAISERROR(N'Invalid @StartTransaction Specified. Specify either the exact (integer) ID from dda.audits.transaction_id OR a formatted dddd-doy-####### value as provided by dda.get_audit_data.', 16, 1);
			RETURN -80;
		END;

		IF @txDate IS NULL BEGIN 
			RAISERROR(N'Invalid @StartTransaction Specified. Specify either the exact (integer) ID from dda.audits.transaction_id OR a formatted dddd-doy-####### value as provided by dda.get_audit_data.', 16, 1);
			RETURN -81;
		  END;
		ELSE BEGIN 
			SET @transactionIdClause = @transactionIdClause + N' AND [timestamp] >= ''' + CONVERT(sysname, @txDate, 121) + N''' AND [timestamp] < ''' + CONVERT(sysname, DATEADD(DAY, 1, @txDate), 121) + N'''';
		END;
		
		SET @transactionIdClause = @transactionIdClause + N')';

		IF @predicated = 1 SET @transactionIdClause = @newlineAndTabs + N'AND ' + @transactionIdClause;
		SET @predicated = 1;
	END;

	SET @coreQuery = REPLACE(@coreQuery, N'{TimeFilters}', @timeFilters);
	SET @coreQuery = REPLACE(@coreQuery, N'{Users}', @users);
	SET @coreQuery = REPLACE(@coreQuery, N'{Tables}', @tables);
	SET @coreQuery = REPLACE(@coreQuery, N'{AuditID}', @auditIdClause);
	SET @coreQuery = REPLACE(@coreQuery, N'{TransactionID}', @transactionIdClause);
	
	DECLARE @coreJSON nvarchar(MAX);
	EXEC sp_executesql 
		@coreQuery, 
		N'@FromIndex int, @ToIndex int, @coreJSON nvarchar(MAX) OUTPUT', 
		@FromIndex = @FromIndex, 
		@ToIndex = @ToIndex, 
		@coreJSON = @coreJSON OUTPUT;

	DECLARE @matchedRows int;
	CREATE TABLE #raw_data ( 
		[row_number] int NOT NULL,
		[total_rows] int NOT NULL, 
		[audit_id] int NOT NULL,
		[timestamp] datetime NOT NULL,
		[table] sysname NOT NULL,
		[translated_table] sysname NULL,
		[user] sysname NOT NULL,
		[operation_type] char(6) NOT NULL,
		[transaction_id] int NOT NULL,
		[row_count] int NOT NULL,
		[change_details] nvarchar(max) NULL, 
		[translated_json] nvarchar(MAX) NULL
	);

	INSERT INTO [#raw_data] (
		[x].[row_number],
		[x].[total_rows],
		[x].[audit_id],
		[a].[timestamp],
		[a].[table],
		[a].[user],
		[a].[operation_type],
		[a].[transaction_id],
		[a].[row_count],
		[a].[change_details]
	)
	SELECT 
		[x].[row_number],
		[x].[total_rows],
		[x].[audit_id],
		[a].[timestamp],
		[a].[schema] + N'.' + [a].[table] [table],
		[a].[user],
		[a].[operation],
		[a].[transaction_id],
		[a].[row_count],
		[a].[audit] [change_details]
	FROM 
		OPENJSON(@coreJSON) WITH ([row_number] int, [total_rows] int, [audit_id] int) [x]
		INNER JOIN dda.[audits] [a] ON [x].[audit_id] = [a].[audit_id];

	SELECT @matchedRows = @@ROWCOUNT;

	/* Short-circuit options for transforms: */
	IF (@matchedRows < 1) OR (@TransformOutput <> 1) GOTO Final_Projection;

	/* Translate table-names: */
	UPDATE x 
	SET 
		[x].[translated_table] = CASE WHEN t.[translated_name] IS NULL THEN x.[table] ELSE t.[translated_name] END
	FROM 
		[#raw_data] x 
		LEFT OUTER JOIN [dda].[translation_tables] t ON x.[table] = t.[table_name];

	CREATE TABLE #scalar ( 
		[scalar_id] int IDENTITY(1,1) NOT NULL, 
		[audit_id] int NOT NULL, 
		[operation_type] char(6) NOT NULL,
		[row_count] int NOT NULL,
		[row_number] int NOT NULL, 
		[json_row_id] int NOT NULL, 
		[source_table] sysname NOT NULL, 
		[change_details] nvarchar(MAX) NOT NULL, 
		[translate_keys] nvarchar(MAX) NULL, 
		[translated_details] nvarchar(MAX) NULL
	);

	WITH distinct_json_rows AS ( 
		SELECT 
			[x].[audit_id],
			[x].[operation_type],
			[x].[row_count],
			[x].[row_number], 
			[r].[Key] [json_row_id], 
			[x].[table], 
			N'[' + [r].[Value] + N']' [change_details]  /* NOTE: without [surrounding brackets], shred no-worky down below... */
		FROM 
			[#raw_data] x 
			CROSS APPLY OPENJSON(JSON_QUERY([x].[change_details], N'$')) r 
		WHERE 
			[x].[row_count] > 1
	) 

	INSERT INTO [#scalar] (
		[audit_id],
		[operation_type],
		[row_count],
		[row_number],
		[json_row_id],
		[source_table],
		[change_details]
	)
	SELECT 
		[audit_id],
		[operation_type],
		[row_count],
		[row_number],
		[json_row_id],
		[table],
		[change_details]
	FROM 
		[distinct_json_rows]

	INSERT INTO [#scalar] (
		[audit_id],
		[operation_type],
		[row_count],
		[row_number],
		[json_row_id],
		[source_table],
		[change_details]
	)
	SELECT 
		[audit_id],
		[operation_type],
		1 [row_count], 
		[row_number],
		0 [json_row_id],
		[table],
		[change_details]
	FROM 
		[#raw_data]
	WHERE
		[row_count] = 1;

	CREATE TABLE [#nodes] ( 
		[node_id] int IDENTITY(1,1) NOT NULL, 
		[audit_id] int NOT NULL,
		[operation_type] char(6) NOT NULL,
		[row_number] int NOT NULL, 
		[json_row_id] int NOT NULL,
		[node_type] sysname NOT NULL,
		[source_table] sysname NOT NULL, 
		[parent_json] nvarchar(MAX) NOT NULL,
		[current_json] nvarchar(MAX) NULL,
		[original_column] sysname NOT NULL, 
		[original_value] nvarchar(MAX) NULL, 
		[original_value_type] int NOT NULL, 
		[translated_value] nvarchar(MAX) NULL, 
		[translated_column] sysname NULL, 
		[translated_value_type] int NULL 
	);

	WITH [keys] AS ( 
		SELECT 
			[x].[audit_id],
			[x].[operation_type],
			[x].[row_number],
			[x].[json_row_id],
			N'key' [node_type],
			[x].[source_table],
			[x].[change_details] [parent_json],
			[z].[Value] [current_json],
			[y].[Key] [original_column],
			ISNULL([y].[Value], N'null') [original_value],
			[y].[Type] [original_value_type]
		FROM 
			[#scalar] x 
			OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], N'$[0].key'), N'$') z 
			CROSS APPLY OPENJSON([z].[Value], N'$') y
	)

	INSERT INTO [#nodes] (
		[audit_id],
		[operation_type],
		[row_number],
		[json_row_id],
		[node_type],
		[source_table],
		[parent_json],
		[current_json],
		[original_column],
		[original_value],
		[original_value_type]
	)
	SELECT 
		[audit_id],
		[operation_type],
		[row_number],
		[json_row_id],
		[node_type],
		[source_table],
		[parent_json],
		[current_json],
		[original_column],
		[original_value],
		[original_value_type] 
	FROM 
		[keys];
	
	WITH [details] AS ( 
		SELECT 
			[x].[audit_id],
			[x].[operation_type],
			[x].[row_number],
			[x].[json_row_id],
			N'detail' [node_type],
			[x].[source_table],
			[x].[change_details] [parent_json],
			[z].[Value] [current_json],
			[y].[Key] [original_column],
			ISNULL([y].[Value], N'null') [original_value],
			[y].[Type] [original_value_type]
		FROM 
			[#scalar] x 
			OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], N'$[0].detail'), N'$') z 
			CROSS APPLY OPENJSON([z].[Value], N'$') y
		WHERE 
			[y].[Value] NOT LIKE '%from":%"to":%'
	) 

	INSERT INTO [#nodes] (
		[audit_id],
		[operation_type],
		[row_number],
		[json_row_id],
		[node_type],
		[source_table],
		[parent_json],
		[current_json],
		[original_column],
		[original_value],
		[original_value_type]
	)
	SELECT 
		[audit_id],
		[operation_type],
		[row_number],
		[json_row_id],
		[node_type],
		[source_table],
		[parent_json],
		[current_json],
		[original_column],
		[original_value],
		[original_value_type] 
	FROM 
		[details];

	/* Extract from/to child nodes for UPDATES: */
	SELECT 
		[x].[audit_id],
		[x].[operation_type],
		[x].[row_number],
		[x].[json_row_id],
		N'detail' [node_type],
		[x].[source_table],
		[x].[change_details] [parent_json],
		[z].[Value] [current_json],
		[y].[Key] [original_column],
		ISNULL([y].[Value], N'null') [original_value],
		[y].[Type] [original_value_type]
	INTO 
		#updates
	FROM 
		[#scalar] x 
		OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], N'$[0].detail'), N'$') z 
		CROSS APPLY OPENJSON([z].[Value], N'$') y
	WHERE 
		[y].[Type] = 5 AND
		[y].[Value] LIKE '%from":%"to":%'
	OPTION (MAXDOP 1);

	WITH [from_to] AS ( 

		SELECT 
			[x].[audit_id],
			[x].[operation_type],
			[x].[row_number],
			[x].[json_row_id],
			[y].[Key] [node_type],
			[x].[source_table],
			[x].[parent_json],
			[x].[current_json],
			[x].[original_column],
			ISNULL([y].[Value], N'null') [original_value], 
			[y].[Type] [original_value_type]
		FROM 
			[#updates] x
			CROSS APPLY OPENJSON([x].[original_value], N'$') y
	)

	INSERT INTO [#nodes] (
		[audit_id],
		[operation_type],
		[row_number],
		[json_row_id],
		[node_type],
		[source_table],
		[parent_json],
		[current_json],
		[original_column],
		[original_value],
		[original_value_type]
	)
	SELECT 
		[audit_id],
		[operation_type],
		[row_number],
		[json_row_id],
		[node_type],
		[source_table],
		[parent_json],
		[current_json],
		[original_column],
		[original_value],
		[original_value_type] 
	FROM 
		[from_to];	
	
	/* Translate Column Names: */
	UPDATE x 
	SET 
		x.[translated_column] = [c].[translated_name]
	FROM 
		[#nodes] x 
		LEFT OUTER JOIN dda.[translation_columns] c ON [x].[source_table] COLLATE SQL_Latin1_General_CP1_CI_AS = [c].[table_name] AND [x].[original_column] COLLATE SQL_Latin1_General_CP1_CI_AS = [c].[column_name]
	WHERE 
		x.[translated_column] IS NULL; 

	CREATE TABLE #translation_key_values (
		[row_id] int IDENTITY(1,1) NOT NULL, 
		[source_table] sysname NOT NULL, 
		[source_column] sysname NOT NULL, 
		[translation_key] nvarchar(MAX) NOT NULL, 
		[translation_value] nvarchar(MAX) NOT NULL, 
		[target_json_type] tinyint NULL,
		[weight] int NOT NULL DEFAULT (1)
	);	

	IF EXISTS (SELECT NULL FROM [#nodes] n LEFT OUTER JOIN dda.[translation_keys] tk ON [n].[source_table] = [tk].[table_name] AND [n].[original_column] = [tk].[column_name] WHERE [tk].[table_name] IS NOT NULL) BEGIN 

		DECLARE @sourceTable sysname, @sourceColumn sysname, @translationTable sysname, @translationKey nvarchar(MAX), @translationValue nvarchar(MAX);
		DECLARE @translationSql nvarchar(MAX);

		DECLARE [translator] CURSOR LOCAL FAST_FORWARD FOR 
		SELECT DISTINCT
			[tk].[table_name], 
			[tk].[column_name], 
			[tk].[key_table],
			[tk].[key_column], 
			[tk].[value_column]
		FROM 
			dda.[translation_keys] tk	
			LEFT OUTER JOIN [#nodes] x ON [tk].[table_name] = [x].[source_table] AND [tk].[column_name] = [x].[original_column]
		WHERE 
			[x].[source_table] IS NOT NULL AND [x].[original_column] IS NOT NULL;
				
		OPEN [translator];
		FETCH NEXT FROM [translator] INTO @sourceTable, @sourceColumn, @translationTable, @translationKey, @translationValue;
		
		WHILE @@FETCH_STATUS = 0 BEGIN
		
			SET @translationSql = N'INSERT INTO #translation_key_values ([source_table], [source_column], [translation_key], [translation_value]) 
				SELECT @sourceTable [source_table], @sourceColumn [source_column], ' + QUOTENAME(@translationKey) + N' [translation_key], ' + QUOTENAME(@translationValue) + N' [translation_value] 
				FROM 
					' + @translationTable + N';'

			EXEC sp_executesql 
				@translationSql, 
				N'@sourceTable sysname, @sourceColumn sysname', 
				@sourceTable = @sourceTable, 
				@sourceColumn = @sourceColumn;			

			FETCH NEXT FROM [translator] INTO @sourceTable, @sourceColumn, @translationTable, @translationKey, @translationValue;
		END;
		
		CLOSE [translator];
		DEALLOCATE [translator];

	END;

	INSERT INTO [#translation_key_values] (
		[source_table],
		[source_column],
		[translation_key],
		[translation_value], 
		[target_json_type],
		[weight]
	)
	SELECT DISTINCT /*  TODO: tired... not sure why I'm tolerating this code-smell/nastiness - but need to address it... */
		v.[table_name] [source_table], 
		v.[column_name] [source_column], 
		v.[key_value] [translation_key],
		v.[translation_value], 
		v.[target_json_type],
		2 [weight]
	FROM 
		[#nodes] x 
		INNER JOIN [dda].[translation_values] v ON x.[source_table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[original_column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name];

	/* Explicit values in dda.translation_values can/will/should OVERWRITE any mappings or translations provided by FKs defined in dda.translation_keys - so remove lower-ranked duplicates: */
	WITH duplicates AS ( 
		SELECT
			row_id
		FROM 
			[#translation_key_values] t1 
			WHERE EXISTS ( 
				SELECT NULL 
				FROM [#translation_key_values] t2 
				WHERE 
					t1.[source_table] = t2.[source_table]
					AND t1.[source_column] = t2.[source_column]
					AND t1.[translation_key] = t2.[translation_key]
				GROUP BY 
					t2.[source_table], t2.[source_column], t2.[translation_key]
				HAVING 
					COUNT(*) > 1 
					AND MAX(t2.[weight]) > t1.[weight]
			)
	)

	DELETE x 
	FROM 
		[#translation_key_values] x 
		INNER JOIN [duplicates] d ON [x].[row_id] = [d].[row_id];

	IF EXISTS (SELECT NULL FROM [#translation_key_values]) BEGIN 
		UPDATE x 
		SET 
			x.[translated_value] = v.[translation_value], 
			x.[translated_value_type] = CASE WHEN v.[target_json_type] IS NOT NULL THEN [v].[target_json_type] ELSE dda.[get_json_data_type](v.[translation_value]) END
		FROM 
			[#nodes] x 
			INNER JOIN [#translation_key_values] v ON 
				[x].[source_table] COLLATE SQL_Latin1_General_CP1_CI_AS = [v].[source_table] 
				AND x.[original_column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_column] 
				AND x.[original_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[translation_key];
	END;

	/* RE-ASSEMBLY */

	/* Start with from-to values and translations: */
	SELECT 
		ISNULL([translated_column], [original_column]) [column_name], 
		LEAD(ISNULL([translated_column], [original_column]), 1, NULL) OVER(PARTITION BY [row_number], [json_row_id] ORDER BY [node_id]) [next_column_name],
		[row_number], 
		[json_row_id], 
		[node_type],
		ISNULL([translated_value], [original_value]) [value], 
		ISNULL([translated_value_type], [original_value_type]) [value_type], 
		[node_id]
	INTO 
		#parts
	FROM 
		[#nodes]
	WHERE 
		[node_type] IN (N'from', N'to');

	WITH [froms] AS ( 
		SELECT 
			[x].[column_name],
			[x].[row_number],
			[x].[json_row_id],
			CASE WHEN [x].[value_type] = 1 THEN STRING_ESCAPE([x].[value], 'json') ELSE [x].[value] END [value], 
			[x].[value_type],
			[x].[node_id] 
		FROM 
			[#parts] x
		WHERE 
			[node_type] = N'from'
	), 
	[tos] AS ( 
		SELECT 
			[x].[column_name],
			[x].[row_number],
			[x].[json_row_id],
			CASE WHEN [x].[value_type] = 1 THEN STRING_ESCAPE([x].[value], 'json') ELSE [x].[value] END [value],
			[x].[value_type]
		FROM 
			froms f 
			INNER JOIN [#parts] x ON f.[node_id] + 1 = x.[node_id]
	), 
	[flattened] AS ( 

		SELECT 
			[f].[row_number],
			[f].[json_row_id],
			[f].[node_id],
			N'"' + [f].[column_name] + N'":{"from":' + CASE WHEN [f].[value_type] = 1 THEN N'"' + [f].[value] + N'"' ELSE [f].[value] END + ',"to":' + CASE WHEN [t].[value_type] = 1 THEN N'"' + [t].[value] + N'"' ELSE [t].[value] END + N'}' [collapsed]
		FROM 
			[froms] f 
			INNER JOIN [tos] t ON f.[row_number] = t.[row_number] AND f.[json_row_id] = t.[json_row_id] AND f.[column_name] = t.[column_name]
	), 
	[aggregated] AS ( 
		SELECT 
			[row_number],
			[json_row_id],
			N'{' +
				STRING_AGG([collapsed], N',') WITHIN GROUP (ORDER BY [row_number], [json_row_id], [node_id]) +
			N'}' [detail]
		FROM 
			[flattened]
		GROUP BY 
			[row_number], [json_row_id]
	)

	UPDATE x 
	SET 
		[x].[translated_details] = a.[detail]
	FROM 
		[#scalar] x 
		INNER JOIN [aggregated] a ON x.[row_number] = a.[row_number] AND x.[json_row_id] = a.[json_row_id];

	/* Re-encode de-encoded (or non-encoded (translation)) JSON: */
	UPDATE [#nodes] 
	SET 
		[original_value] = CASE WHEN [original_value_type] = 1 THEN STRING_ESCAPE([original_value], 'json') ELSE [original_value] END, 
		[translated_value] = CASE WHEN [translated_value_type] = 1 THEN STRING_ESCAPE([translated_value], 'json') ELSE [translated_value] END
	WHERE 
		ISNULL([translated_value_type], [original_value_type]) = 1; 

	/* Serialize Details (for non UPDATEs - they've already been handled above) */
	WITH [flattened] AS ( 
		SELECT 
			[row_number], 
			[json_row_id], 
			[node_id],
			N'"' + ISNULL([translated_column], [original_column]) + N'":' + CASE WHEN ISNULL([translated_value_type], [original_value_type]) = 1 THEN N'"' + ISNULL([translated_value], [original_value]) + N'"' ELSE ISNULL([translated_value], [original_value]) END [collapsed]
		FROM 
			[#nodes] 
		WHERE 
			[node_type] = N'detail'
	), 
	[aggregated] AS ( 
		SELECT 
			[row_number],
			[json_row_id], 
			N'{' + 
				STRING_AGG([collapsed], N',') WITHIN GROUP (ORDER BY [row_number], [json_row_id], [node_id]) +
			N'}' [detail]
		FROM 
			[flattened]
		GROUP BY 
			[row_number],
			[json_row_id]
	)

	UPDATE x 
	SET 
		[x].[translated_details] = a.[detail]
	FROM 
		[#scalar] x 
		INNER JOIN [aggregated] a ON x.[row_number] = a.[row_number] AND x.[json_row_id] = a.[json_row_id]
	WHERE 
		x.[translated_details] IS NULL;

	/* Serialized Keys */
	WITH [flattened] AS (  
		SELECT 
			[row_number], 
			[json_row_id], 
			[node_id],
			N'"' + ISNULL([translated_column], [original_column]) + N'":' + CASE WHEN ISNULL([translated_value_type], [original_value_type]) = 1 THEN N'"' + ISNULL([translated_value], [original_value]) + N'"' ELSE ISNULL([translated_value], [original_value]) END [collapsed]
		FROM 
			[#nodes] 
		WHERE 
			[node_type] = N'key'
	),
	[aggregated] AS ( 
		SELECT 
			[row_number],
			[json_row_id], 
			N'{' + 
				STRING_AGG([collapsed], N',') WITHIN GROUP (ORDER BY [row_number], [json_row_id], [node_id]) +
			N'}' [keys]
		FROM 
			flattened 
		GROUP BY 
			[row_number],
			[json_row_id]			
	)

	UPDATE x 
	SET 
		x.[translate_keys] = a.[keys]
	FROM 
		[#scalar] x 
		INNER JOIN [aggregated] a ON x.[row_number] = a.[row_number] AND x.[json_row_id] = a.[json_row_id];

	/* MAP translated JSON back to #raw_data - starting with scalar rows, then move to multi-row JSON ... */
	UPDATE x 
	SET 
	 	x.[translated_json] = N'[{"key":[' + s.[translate_keys] + N'],"detail":[' + s.[translated_details] + N']}]'
	FROM 
		[#raw_data] x 
		INNER JOIN [#scalar] s ON [x].[row_number] = [s].[row_number]
	WHERE 
		x.[row_count] = 1;

	WITH [flattened] AS ( 
		SELECT 
			[row_number], 
			N'[' +
				STRING_AGG(N'{"key":[' + [translate_keys] + N'],"detail":[' + [translated_details] + N']}', N',') WITHIN GROUP(ORDER BY [row_number], [json_row_id]) + 
			N']' [collapsed]
		FROM 
			[#scalar] 
		WHERE 
			[row_count] > 1
		GROUP BY 
			[row_number]
	) 

	UPDATE x 
	SET 
		x.[translated_json] = f.[collapsed]
	FROM 
		[#raw_data] x 
		INNER JOIN [flattened] f ON [x].[row_number] = [f].[row_number] 
	WHERE 
		x.[translated_json] IS NULL;

Final_Projection: 

	SELECT 
		[row_number],
		[total_rows],
		[audit_id],
		[timestamp],
		[user],
		ISNULL([translated_table], [table]) [table],
		CONCAT(DATEPART(YEAR, [timestamp]), N'-', RIGHT(N'000' + DATENAME(DAYOFYEAR, [timestamp]), 3), N'-', RIGHT(N'000000000' + CAST([transaction_id] AS sysname), 9)) [transaction_id],
		[operation_type],
		[row_count],
		CASE WHEN [translated_json] IS NULL AND [change_details] LIKE N'%,"dump":%' THEN [change_details] ELSE ISNULL([translated_json], [change_details]) END [change_details] 
	FROM 
		[#raw_data]
	ORDER BY 
		[row_number];

	RETURN 0;
GO