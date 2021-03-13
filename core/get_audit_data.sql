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
			SELECT @startTx = RIGHT(@StartTransactionID, 9);

			SET @txDate = CAST(CAST(@year AS sysname) + N'-01-01' AS datetime);
			SET @txDate = DATEADD(DAY, @doy - 1, @txDate);
		  END;
		ELSE BEGIN 
			IF @TransactionDate IS NOT NULL SET @txDate = @TransactionDate;
			SET @startTx = TRY_CAST(@StartTransactionID AS int);
		END;

		IF @EndTransactionID IS NOT NULL BEGIN 
			IF @EndTransactionID LIKE N'%-%' BEGIN 
				SET @endTx = RIGHT(@EndTransactionID, 9);
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

		IF @txDate IS NOT NULL BEGIN 
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
		[translated_change_key] nvarchar(MAX) NULL, 
		[translated_change_detail] nvarchar(MAX) NULL, 
		[translated_multi_row] nvarchar(MAX) NULL
	);

	-- NOTE: INSERT + EXEC (dynamic-SQL with everything needed from dda.audits in a single 'gulp') would make more sense here. 
	--		BUT, INSERT + EXEC causes dreaded "INSERT EXEC can't be nested..." error if/when UNIT tests are used to test this code. 
	--			So, this 'hack' of grabbing JSON (dynamically), shredding it, and JOINing 'back' to dda.audits... exists below):
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

	-- short-circuit options for transforms:
	IF (@matchedRows < 1) OR (@TransformOutput <> 1) GOTO Final_Projection;

	-- table translations: 
	UPDATE x 
	SET 
		[x].[translated_table] = CASE WHEN t.[translated_name] IS NULL THEN x.[table] ELSE t.[translated_name] END
	FROM 
		[#raw_data] x 
		LEFT OUTER JOIN [dda].[translation_tables] t ON x.[table] = t.[table_name];
		
	CREATE TABLE [#key_value_pairs] ( 
		[kvp_id] int IDENTITY(1,1) NOT NULL, 
		[kvp_type] sysname NOT NULL, 
		[row_number] int NOT NULL,
		[json_row_id] int NOT NULL DEFAULT 0,  -- for 'multi-row' ... rows. 
		[table] sysname NOT NULL, 
		[column] sysname NOT NULL, 
		[translated_column] sysname NULL, 
		[value] nvarchar(MAX) NULL, 
		[value_type] int NOT  NULL,
		[translated_value] sysname NULL, 
		[from_value] nvarchar(MAX) NULL, 
		[translated_from_value] sysname NULL, 
		[to_value] nvarchar(MAX) NULL, 
		[translated_to_value] sysname NULL, 
		[translated_update_value] nvarchar(MAX) NULL
	);

	INSERT INTO [#key_value_pairs] (
		[kvp_type],
		[table],
		[row_number],
		[column],
		[value],
		[value_type]
	)
	SELECT 
		N'key' [kvp_type],
		[x].[table], 
		[x].[row_number],
		[y].[Key] [column], 
		[y].[Value] [value],
		[y].[Type] [value_type]
	FROM 
		[#raw_data] x
		OUTER APPLY OPENJSON(JSON_QUERY(x.[change_details], '$[0].key'), '$') z
		CROSS APPLY OPENJSON(z.[Value], N'$') y
	WHERE 
		x.[row_count] = 1
		AND y.[Key] IS NOT NULL 
		AND y.[Value] IS NOT NULL;

	INSERT INTO [#key_value_pairs] (
		[kvp_type],
		[table],
		[row_number],
		[column],
		[value],
		[value_type]
	)
	SELECT 
		N'detail' [kvp_type],
		[x].[table], 
		[x].[row_number],
		[y].[Key] [column], 
		[y].[Value] [value],
		[y].[Type] [value_type]
	FROM 
		[#raw_data] x 
		OUTER APPLY OPENJSON(JSON_QUERY(x.[change_details], '$[0].detail'), '$') z
		CROSS APPLY OPENJSON(z.[Value], N'$') y
	WHERE 
		x.[row_count] = 1
		AND y.[Key] IS NOT NULL
		AND y.[Value] IS NOT NULL;

	IF EXISTS(SELECT NULL FROM [#raw_data] WHERE [row_count] > 1) BEGIN

		WITH [row_keys] AS ( 
			SELECT 
				[x].[table], 
				[x].[row_number],
				[r].[Key] [json_row_id], 
				[r].[Value] [change_details]
			FROM 
				[#raw_data] x 
				CROSS APPLY OPENJSON(JSON_QUERY([x].[change_details], N'$')) r
			WHERE 
				x.[row_count] > 1
		)

		INSERT INTO [#key_value_pairs] (
			[kvp_type],
			[table],
			[row_number],
			[json_row_id],
			[column],
			[value],
			[value_type]
		)
		SELECT 
			N'key' [kvp_type], 
			[x].[table], 
			[x].[row_number],
			[x].[json_row_id], 
			[y].[Key] [column], 
			[y].[Value] [value],
			[y].[Type] [value_type]
		FROM 
			[row_keys] x
			OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], '$.key'), '$') z
			CROSS APPLY OPENJSON(z.[Value], N'$') y;

		-- ditto, for details:
		WITH [row_details] AS ( 
			SELECT 
				[x].[table], 
				[x].[row_number],
				[r].[Key] [json_row_id], 
				[r].[Value] [change_details]
			FROM 
				[#raw_data] x 
				CROSS APPLY OPENJSON(JSON_QUERY([x].[change_details], N'$')) r
			WHERE 
				x.[row_count] > 1
		)

		INSERT INTO [#key_value_pairs] (
			[kvp_type],
			[table],
			[row_number],
			[json_row_id],
			[column],
			[value],
			[value_type]
		)
		SELECT 
			N'detail' [kvp_type], 
			[x].[table], 
			[x].[row_number],
			[x].[json_row_id], 
			[y].[Key] [column], 
			[y].[Value] [value],
			[y].[Type] [value_type]
		FROM 
			[row_details] x
			OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], '$.detail'), '$') z
			CROSS APPLY OPENJSON(z.[Value], N'$') y;
	END;

	UPDATE [#key_value_pairs] 
	SET 
		[from_value] = ISNULL(JSON_VALUE([value], N'$.from'), N'null'), 
		[to_value] = ISNULL(JSON_VALUE([value], N'$.to'), N'null')
	WHERE 
		ISJSON([value]) = 1 AND [value] LIKE '%from":%"to":%';

	-- address translation_keys: 
	IF EXISTS (SELECT NULL FROM [#key_value_pairs] kvp LEFT OUTER JOIN [dda].[translation_keys] tk ON [kvp].[table] = tk.[table_name] AND kvp.[column] = tk.[column_name] WHERE tk.[table_name] IS NOT NULL) BEGIN
		
		CREATE TABLE #translation_key_values (
			row_id int IDENTITY(1,1) NOT NULL, 
			source_table sysname NOT NULL, 
			source_column sysname NOT NULL, 
			translation_key nvarchar(MAX) NOT NULL, 
			translation_value nvarchar(MAX) NOT NULL
		);
			
		DECLARE @sourceTable sysname, @sourceColumn sysname, @translationTable sysname, @translationKey nvarchar(MAX), @translationValue nvarchar(MAX);
		DECLARE @translationSql nvarchar(MAX);

		DECLARE [translator] CURSOR LOCAL FAST_FORWARD FOR 
		SELECT DISTINCT
			tk.[table_name], 
			tk.[column_name], 
			tk.[key_table],
			tk.[key_column], 
			tk.[value_column]
		FROM 
			dda.[translation_keys] tk	
			LEFT OUTER JOIN [#key_value_pairs] x ON tk.[table_name] = x.[table] AND tk.[column_name] = x.[column]
		WHERE 
			x.[table] IS NOT NULL AND x.[column] IS NOT NULL;
				
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

		-- map INSERT/DELETE translations:
		UPDATE x 
		SET 
			x.[translated_value] = v.[translation_value]
		FROM 
			[#key_value_pairs] x 
			LEFT OUTER JOIN #translation_key_values v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_table] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_column] 
			AND x.[value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[translation_key] COLLATE SQL_Latin1_General_CP1_CI_AS
			AND x.[value] NOT LIKE N'{"from":%"to":%';

		-- map FROM / TO translations:
		UPDATE x 
		SET
			x.[translated_from_value] = v.[translation_value]
		FROM 
			[#key_value_pairs] x 
			LEFT OUTER JOIN #translation_key_values v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_table] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_column] 
				AND x.[from_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[translation_key] COLLATE SQL_Latin1_General_CP1_CI_AS
		WHERE 
			[from_value] IS NOT NULL; -- only bother executing UPDATEs vs FROM/TO (UPDATE) values.

		UPDATE x 
		SET
			x.[translated_to_value] = v.[translation_value]
		FROM 
			[#key_value_pairs] x 
			LEFT OUTER JOIN #translation_key_values v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_table] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_column] 
				AND x.[to_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[translation_key] COLLATE SQL_Latin1_General_CP1_CI_AS
		WHERE 
			[to_value] IS NOT NULL; -- ditto... 
	END;
	
	UPDATE x 
	SET 
		x.[translated_column] = c.[translated_name], 
		x.[translated_value] = ISNULL(v.[translation_value], x.[translated_value])
	FROM 
		[#key_value_pairs] x
		LEFT OUTER JOIN dda.[translation_columns] c ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = c.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = c.[column_name]
		LEFT OUTER JOIN dda.[translation_values] v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name] 
			AND x.[value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[key_value] COLLATE SQL_Latin1_General_CP1_CI_AS
			AND x.[value] NOT LIKE N'{"from":%"to":%';

	-- Stage from/to value translations:
	UPDATE x 
	SET
		x.[translated_from_value] = ISNULL(v.[translation_value], x.[translated_from_value])
	FROM 
		[#key_value_pairs] x 
		LEFT OUTER JOIN dda.[translation_values] v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name] 
			AND x.[from_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[key_value] COLLATE SQL_Latin1_General_CP1_CI_AS
	WHERE 
		[from_value] IS NOT NULL; -- only bother executing UPDATEs vs FROM/TO (UPDATE) values.

	UPDATE x 
	SET
		x.[translated_to_value] = ISNULL(v.[translation_value], x.[translated_to_value])
	FROM 
		[#key_value_pairs] x 
		LEFT OUTER JOIN dda.[translation_values] v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name] 
			AND x.[to_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[key_value] COLLATE SQL_Latin1_General_CP1_CI_AS
	WHERE 
		[to_value] IS NOT NULL; -- ditto... 

	-- Serialize from/to values (UPDATE summaries) back down to JSON:
	UPDATE [#key_value_pairs] 
	SET 
		[translated_update_value] = N'{"from":' + CASE 
				WHEN dda.[get_json_data_type](ISNULL([translated_from_value], [from_value])) = 1 THEN N'"' + ISNULL([translated_from_value], [from_value]) + N'"'
				ELSE ISNULL([translated_from_value], [from_value])
			END + N', "to":' + CASE 
				WHEN dda.[get_json_data_type](ISNULL([translated_to_value], [to_value])) = 1 THEN N'"' + ISNULL([translated_to_value], [to_value]) + N'"'
				ELSE + ISNULL([translated_to_value], [to_value])
			END + N'}'
	WHERE 
		[translated_from_value] IS NOT NULL 
		OR 
		[translated_to_value] IS NOT NULL;

	-- Collapse translations + non-translations down to a single working set: 
	WITH core AS ( 
		SELECT 
			ROW_NUMBER() OVER (ORDER BY [kvp_id]) [sort_id],
			[kvp_type], 
			[row_number], 
			[json_row_id],
			ISNULL([translated_column], [column]) [column], 
			CASE 
				WHEN [value_type] = 5 THEN ISNULL([translated_update_value], [value])
				ELSE ISNULL([translated_value], [value])
			END [value], 
			[value_type]
		FROM 
			[#key_value_pairs]
		WHERE 
			[kvp_type] = N'key'
	), 
	[keys] AS (
		SELECT 
			[sort_id],
			[kvp_type],
			COUNT(*) OVER (PARTITION BY [row_number], [json_row_id]) [kvp_count], 
			ROW_NUMBER() OVER (PARTITION BY [row_number], [json_row_id] ORDER BY [sort_id]) [current_kvp],
			[row_number],
			[json_row_id],
			[column],
			[value],
			[value_type]
		FROM 
			core
	)

	SELECT 
		[sort_id],
		[row_number],
		[json_row_id],
		[kvp_type],
		[kvp_count],
		[current_kvp],
		[column],
		[value],
		[value_type]
	INTO 
		#translated_kvps
	FROM 
		keys;

	WITH core AS ( 
		SELECT 
			ROW_NUMBER() OVER (ORDER BY [kvp_id]) [sort_id],
			[kvp_type], 
			[row_number], 
			[json_row_id],
			[table], 
			ISNULL([translated_column], [column]) [column], 
			CASE 
				WHEN [value_type] = 5 THEN ISNULL([translated_update_value], [value])
				ELSE ISNULL([translated_value], [value])
			END [value], 
			[value_type]
		FROM 
			[#key_value_pairs]
		WHERE 
			[kvp_type] = N'detail'

	), 
	[details] AS (
		SELECT 
			[sort_id],
			[kvp_type],
			COUNT(*) OVER (PARTITION BY [row_number], [json_row_id]) [kvp_count], 
			ROW_NUMBER() OVER (PARTITION BY [row_number], [json_row_id] ORDER BY [sort_id]) [current_kvp],
			[row_number],
			[json_row_id],
			[column],
			[value],
			[value_type]
		FROM 
			core
	)

	INSERT INTO [#translated_kvps] (
		[sort_id],
		[row_number],
		[json_row_id],
		[kvp_type],
		[kvp_count],
		[current_kvp],
		[column],
		[value],
		[value_type]
	)
	SELECT 
		[sort_id],
		[row_number],
		[json_row_id],
		[kvp_type],
		[kvp_count],
		[current_kvp],
		[column],
		[value],
		[value_type]
	FROM 
		[details];

	-- collapse multi-row results back down to a single 'set'/row of results:
	IF EXISTS (SELECT NULL FROM [#raw_data] WHERE [row_count] > 1) BEGIN 

		WITH [flattened] AS ( 
			SELECT 
				x.[row_number], 
				x.[json_row_id], 
				x.[kvp_type],
				x.[kvp_count], 
				x.[current_kvp], 
				x.[column], 
				x.[value], 
				x.[value_type], 
				x.[sort_id]		
			FROM 
				[#translated_kvps] x
				INNER JOIN [#raw_data] r ON [x].[row_number] = [r].[row_number]
			WHERE 
				r.[row_count] > 1
		), 
		[keys] AS ( 
			SELECT 
				*
			FROM 
				[flattened]
			WHERE 
				[flattened].[kvp_type] = N'key'

		), 
		[details] AS ( 
			SELECT 
				*
			FROM 
				[flattened]
			WHERE 
				[flattened].[kvp_type] = N'detail'
		),
		[collapsed] AS (
			SELECT 
				x.[row_number], 
				f.[json_row_id], 
				NULLIF(COALESCE(STUFF(
					(
						SELECT 
							N',' + -- always include (for STUFF() call) - vs conditional include with STRING_AGG()). 
							N'"' + [k].[column] + N'":' + 
							CASE 
								WHEN [k].[value_type] = 1 THEN N'"' + [k].[value] + N'"'
								ELSE [k].[value]
							END  
						FROM 
							[keys] [k]
						WHERE 
							[x].[row_number] = [k].[row_number] 
							AND [f].[json_row_id] = [k].[json_row_id]
						ORDER BY 
							[k].[json_row_id], [k].[current_kvp], [k].[sort_id]
						FOR XML PATH('')
					)
				, 1, 1, N''), N''), N'') [key_data],
				NULLIF(COALESCE(STUFF(
					(
						SELECT
							N',' + 
							N'"' + [d].[column] + N'":' + 
							CASE 
								WHEN [d].[value_type] = 1 THEN N'"' + [d].[value] + N'"'
								ELSE [d].[value]
							END
						FROM 
							[details] [d] 
						WHERE 
							[x].[row_number] = [d].[row_number] 
							AND [f].[json_row_id] = [d].[json_row_id]		
						ORDER BY 
							[d].[json_row_id], [d].[current_kvp], [d].[sort_id]
						FOR XML PATH('')
					)
				, 1, 1, N''), N''), N'') [detail_data]
			FROM 
				[#raw_data] [x]
				INNER JOIN [flattened] f ON [x].[row_number] = f.[row_number]
			GROUP BY 
				[x].[row_number], f.[json_row_id]
		), 
		[serialized] AS ( 
			SELECT 
				[x].[row_number], 
				N'[' + NULLIF(COALESCE(STUFF(
					(
						SELECT 
							N',' + 
							N'{"key": [{' + [c].[key_data] + N'}],"detail":[{' + [c].[detail_data] + N'}]}'
						FROM 
							[collapsed] [c] WHERE [c].[row_number] = [x].[row_number]
						ORDER BY 
							[c].[json_row_id]
						FOR XML PATH('')
					)
				, 1, 1, N''), N''), N'') + N']' [serialized]

			FROM 
				[#raw_data] [x] 
			WHERE 
				[x].[row_count] > 1
		)

		UPDATE [r] 
		SET 
			[r].[translated_multi_row] = [s].[serialized]
		FROM 
			[#raw_data] [r] 
			INNER JOIN [serialized] [s] ON [r].[row_number] = [s].[row_number]	
		WHERE 
			[r].[row_count] > 1
	END;

	-- Serialize KVPs (ordered by row_number) down to JSON: 
	WITH [row_numbers] AS (
		SELECT 
			[row_number] 
		FROM 
			[#raw_data]
		WHERE 
			[row_count] = 1
		GROUP BY 
			[row_number]
	), 
	[keys] AS ( 
		SELECT 
			[x].[row_number], 
			NULLIF(COALESCE(STUFF(
				(
					SELECT 
						N',' + 
						N'"' + [x2].[column] + N'":' +
						CASE 
							WHEN [x2].[value_type] = 1 THEN N'"' + [x2].[value] + N'"'
							ELSE [x2].[value]
						END 
					FROM 
						[#translated_kvps] x2 WHERE [x].[row_number] = [x2].[row_number] AND [x2].[kvp_type] = N'key'
					ORDER BY 
						[x2].[json_row_id], [x2].[current_kvp], [x2].[sort_id]
					FOR XML PATH('')
					
				)
			, 1, 1, N''), N''), N'') [key_data]

		FROM 
			[row_numbers] x

	), 
	[details] AS (
		SELECT 
			[x].[row_number], 
			NULLIF(COALESCE(STUFF(
				(
					SELECT 
						N',' + 
						N'"' + [x2].[column] + N'":' +
						CASE 
							WHEN [x2].[value_type] = 1 THEN N'"' + [x2].[value] + N'"'
							ELSE [x2].[value]
						END
					FROM 
						[#translated_kvps] x2 WHERE [x].[row_number] = [x2].[row_number] AND [x2].[kvp_type] = N'detail'
					ORDER BY 
						[x2].[json_row_id], [x2].[current_kvp], [x2].[sort_id]
					FOR XML PATH('')
				)
			, 1, 1, N''), N''), N'') [detail_data]
		FROM 
			[row_numbers] x
	)

	UPDATE [x] 
	SET 
		[x].[translated_change_key] = k.[key_data], 
		[x].[translated_change_detail] = d.[detail_data]
	FROM 
		[#raw_data] x 
		INNER JOIN [keys] k ON [x].[row_number] = [k].[row_number]
		INNER JOIN [details] d ON [x].[row_number] = [d].[row_number]
	WHERE 
		x.row_count = 1;

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
		CASE 
			WHEN [translated_change_key] IS NOT NULL THEN N'[{"key":[{' + [translated_change_key] + N'}],"detail":[{' + [translated_change_detail] + N'}]}]'
			WHEN [translated_multi_row] IS NOT NULL THEN [translated_multi_row] -- this and translated_change_key won't ever BOTH be populated (only one OR the other).
			ELSE [change_details]
		END [change_details] 
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
			RAISERROR(N'Queries against Audit data MUST be constrained - either specify a single @StartAuditID/@StartTransactionID OR @StartTime [+ @EndTIme], or @TargetUsers, or @TargetTables - or a combination of time, table, and user constraints.', 16, 1);
			RETURN -11;
		END;
	END;

	IF @StartTime IS NOT NULL BEGIN 
		IF @StartTime > @EndTime BEGIN
			RAISERROR('@StartTime may not be > @EndTime - please check inputs and try again.', 16, 1);
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
			SELECT @startTx = RIGHT(@StartTransactionID, 9);

			SET @txDate = CAST(CAST(@year AS sysname) + N'-01-01' AS datetime);
			SET @txDate = DATEADD(DAY, @doy - 1, @txDate);
		  END;
		ELSE BEGIN 
			IF @TransactionDate IS NOT NULL SET @txDate = @TransactionDate;
			SET @startTx = TRY_CAST(@StartTransactionID AS int);
		END;

		IF @EndTransactionID IS NOT NULL BEGIN 
			IF @EndTransactionID LIKE N'%-%' BEGIN 
				SET @endTx = RIGHT(@EndTransactionID, 9);
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

		IF @txDate IS NOT NULL BEGIN 
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
		[translated_change_key] nvarchar(MAX) NULL, 
		[translated_change_detail] nvarchar(MAX) NULL, 
		[translated_multi_row] nvarchar(MAX) NULL
	);

	-- NOTE: INSERT + EXEC (dynamic-SQL with everything needed from dda.audits in a single 'gulp') would make more sense here. 
	--		BUT, INSERT + EXEC causes dreaded "INSERT EXEC can't be nested..." error if/when UNIT tests are used to test this code. 
	--			So, this 'hack' of grabbing JSON (dynamically), shredding it, and JOINing 'back' to dda.audits... exists below):
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

	-- short-circuit options for transforms:
	IF (@matchedRows < 1) OR (@TransformOutput <> 1) GOTO Final_Projection;

	-- table translations: 
	UPDATE x 
	SET 
		[x].[translated_table] = CASE WHEN t.[translated_name] IS NULL THEN x.[table] ELSE t.[translated_name] END
	FROM 
		[#raw_data] x 
		LEFT OUTER JOIN [dda].[translation_tables] t ON x.[table] = t.[table_name];
		
	CREATE TABLE [#key_value_pairs] ( 
		[kvp_id] int IDENTITY(1,1) NOT NULL, 
		[kvp_type] sysname NOT NULL, 
		[row_number] int NOT NULL,
		[json_row_id] int NOT NULL DEFAULT 0,  -- for 'multi-row' ... rows. 
		[table] sysname NOT NULL, 
		[column] sysname NOT NULL, 
		[translated_column] sysname NULL, 
		[value] nvarchar(MAX) NULL, 
		[value_type] int NOT  NULL,
		[translated_value] sysname NULL, 
		[from_value] nvarchar(MAX) NULL, 
		[translated_from_value] sysname NULL, 
		[to_value] nvarchar(MAX) NULL, 
		[translated_to_value] sysname NULL, 
		[translated_update_value] nvarchar(MAX) NULL
	);

	INSERT INTO [#key_value_pairs] (
		[kvp_type],
		[table],
		[row_number],
		[column],
		[value],
		[value_type]
	)
	SELECT 
		N'key' [kvp_type],
		[x].[table], 
		[x].[row_number],
		[y].[Key] [column], 
		[y].[Value] [value],
		[y].[Type] [value_type]
	FROM 
		[#raw_data] x
		OUTER APPLY OPENJSON(JSON_QUERY(x.[change_details], '$[0].key'), '$') z
		CROSS APPLY OPENJSON(z.[Value], N'$') y
	WHERE 
		x.[row_count] = 1
		AND y.[Key] IS NOT NULL 
		AND y.[Value] IS NOT NULL;

	INSERT INTO [#key_value_pairs] (
		[kvp_type],
		[table],
		[row_number],
		[column],
		[value],
		[value_type]
	)
	SELECT 
		N'detail' [kvp_type],
		[x].[table], 
		[x].[row_number],
		[y].[Key] [column], 
		[y].[Value] [value],
		[y].[Type] [value_type]
	FROM 
		[#raw_data] x 
		OUTER APPLY OPENJSON(JSON_QUERY(x.[change_details], '$[0].detail'), '$') z
		CROSS APPLY OPENJSON(z.[Value], N'$') y
	WHERE 
		x.[row_count] = 1
		AND y.[Key] IS NOT NULL
		AND y.[Value] IS NOT NULL;

	IF EXISTS(SELECT NULL FROM [#raw_data] WHERE [row_count] > 1) BEGIN

		WITH [row_keys] AS ( 
			SELECT 
				[x].[table], 
				[x].[row_number],
				[r].[Key] [json_row_id], 
				[r].[Value] [change_details]
			FROM 
				[#raw_data] x 
				CROSS APPLY OPENJSON(JSON_QUERY([x].[change_details], N'$')) r
			WHERE 
				x.[row_count] > 1
		)

		INSERT INTO [#key_value_pairs] (
			[kvp_type],
			[table],
			[row_number],
			[json_row_id],
			[column],
			[value],
			[value_type]
		)
		SELECT 
			N'key' [kvp_type], 
			[x].[table], 
			[x].[row_number],
			[x].[json_row_id], 
			[y].[Key] [column], 
			[y].[Value] [value],
			[y].[Type] [value_type]
		FROM 
			[row_keys] x
			OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], '$.key'), '$') z
			CROSS APPLY OPENJSON(z.[Value], N'$') y;

		-- ditto, for details:
		WITH [row_details] AS ( 
			SELECT 
				[x].[table], 
				[x].[row_number],
				[r].[Key] [json_row_id], 
				[r].[Value] [change_details]
			FROM 
				[#raw_data] x 
				CROSS APPLY OPENJSON(JSON_QUERY([x].[change_details], N'$')) r
			WHERE 
				x.[row_count] > 1
		)

		INSERT INTO [#key_value_pairs] (
			[kvp_type],
			[table],
			[row_number],
			[json_row_id],
			[column],
			[value],
			[value_type]
		)
		SELECT 
			N'detail' [kvp_type], 
			[x].[table], 
			[x].[row_number],
			[x].[json_row_id], 
			[y].[Key] [column], 
			[y].[Value] [value],
			[y].[Type] [value_type]
		FROM 
			[row_details] x
			OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], '$.detail'), '$') z
			CROSS APPLY OPENJSON(z.[Value], N'$') y;
	END;

	UPDATE [#key_value_pairs] 
	SET 
		[from_value] = ISNULL(JSON_VALUE([value], N'$.from'), N'null'), 
		[to_value] = ISNULL(JSON_VALUE([value], N'$.to'), N'null')
	WHERE 
		ISJSON([value]) = 1 AND [value] LIKE '%from":%"to":%';

	-- address translation_keys: 
	IF EXISTS (SELECT NULL FROM [#key_value_pairs] kvp LEFT OUTER JOIN [dda].[translation_keys] tk ON [kvp].[table] = tk.[table_name] AND kvp.[column] = tk.[column_name] WHERE tk.[table_name] IS NOT NULL) BEGIN
		
		CREATE TABLE #translation_key_values (
			row_id int IDENTITY(1,1) NOT NULL, 
			source_table sysname NOT NULL, 
			source_column sysname NOT NULL, 
			translation_key nvarchar(MAX) NOT NULL, 
			translation_value nvarchar(MAX) NOT NULL
		);
			
		DECLARE @sourceTable sysname, @sourceColumn sysname, @translationTable sysname, @translationKey nvarchar(MAX), @translationValue nvarchar(MAX);
		DECLARE @translationSql nvarchar(MAX);

		DECLARE [translator] CURSOR LOCAL FAST_FORWARD FOR 
		SELECT DISTINCT
			tk.[table_name], 
			tk.[column_name], 
			tk.[key_table],
			tk.[key_column], 
			tk.[value_column]
		FROM 
			dda.[translation_keys] tk	
			LEFT OUTER JOIN [#key_value_pairs] x ON tk.[table_name] = x.[table] AND tk.[column_name] = x.[column]
		WHERE 
			x.[table] IS NOT NULL AND x.[column] IS NOT NULL;
				
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

		-- map INSERT/DELETE translations:
		UPDATE x 
		SET 
			x.[translated_value] = v.[translation_value]
		FROM 
			[#key_value_pairs] x 
			LEFT OUTER JOIN #translation_key_values v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_table] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_column] 
			AND x.[value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[translation_key] COLLATE SQL_Latin1_General_CP1_CI_AS
			AND x.[value] NOT LIKE N'{"from":%"to":%';

		-- map FROM / TO translations:
		UPDATE x 
		SET
			x.[translated_from_value] = v.[translation_value]
		FROM 
			[#key_value_pairs] x 
			LEFT OUTER JOIN #translation_key_values v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_table] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_column] 
				AND x.[from_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[translation_key] COLLATE SQL_Latin1_General_CP1_CI_AS
		WHERE 
			[from_value] IS NOT NULL; -- only bother executing UPDATEs vs FROM/TO (UPDATE) values.

		UPDATE x 
		SET
			x.[translated_to_value] = v.[translation_value]
		FROM 
			[#key_value_pairs] x 
			LEFT OUTER JOIN #translation_key_values v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_table] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[source_column] 
				AND x.[to_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[translation_key] COLLATE SQL_Latin1_General_CP1_CI_AS
		WHERE 
			[to_value] IS NOT NULL; -- ditto... 
	END;

	UPDATE x 
	SET 
		x.[translated_column] = c.[translated_name], 
		x.[translated_value] = ISNULL(v.[translation_value], x.[translated_value])
	FROM 
		[#key_value_pairs] x
		LEFT OUTER JOIN dda.[translation_columns] c ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = c.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = c.[column_name]
		LEFT OUTER JOIN dda.[translation_values] v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name] 
			AND x.[value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[key_value] COLLATE SQL_Latin1_General_CP1_CI_AS
			AND x.[value] NOT LIKE N'{"from":%"to":%';

	-- Stage from/to value translations:
	UPDATE x 
	SET
		x.[translated_from_value] = ISNULL(v.[translation_value], x.[translated_from_value])
	FROM 
		[#key_value_pairs] x 
		LEFT OUTER JOIN dda.[translation_values] v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name] 
			AND x.[from_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[key_value] COLLATE SQL_Latin1_General_CP1_CI_AS
	WHERE 
		[from_value] IS NOT NULL; -- only bother executing UPDATEs vs FROM/TO (UPDATE) values.

	UPDATE x 
	SET
		x.[translated_to_value] = ISNULL(v.[translation_value], x.[translated_to_value])
	FROM 
		[#key_value_pairs] x 
		LEFT OUTER JOIN dda.[translation_values] v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name] 
			AND x.[to_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[key_value] COLLATE SQL_Latin1_General_CP1_CI_AS
	WHERE 
		[to_value] IS NOT NULL; -- ditto... 

	-- Serialize from/to values (UPDATE summaries) back down to JSON:
	UPDATE [#key_value_pairs] 
	SET 
		[translated_update_value] = N'{"from":' + CASE 
				WHEN dda.[get_json_data_type](ISNULL([translated_from_value], [from_value])) = 1 THEN N'"' + ISNULL([translated_from_value], [from_value]) + N'"'
				ELSE ISNULL([translated_from_value], [from_value])
			END + N', "to":' + CASE 
				WHEN dda.[get_json_data_type](ISNULL([translated_to_value], [to_value])) = 1 THEN N'"' + ISNULL([translated_to_value], [to_value]) + N'"'
				ELSE + ISNULL([translated_to_value], [to_value])
			END + N'}'
	WHERE 
		[translated_from_value] IS NOT NULL 
		OR 
		[translated_to_value] IS NOT NULL;

	-- Collapse translations + non-translations down to a single working set: 
	WITH core AS ( 
		SELECT 
			ROW_NUMBER() OVER (ORDER BY [kvp_id]) [sort_id],
			[kvp_type], 
			[row_number], 
			[json_row_id],
			ISNULL([translated_column], [column]) [column], 
			CASE 
				WHEN [value_type] = 5 THEN ISNULL([translated_update_value], [value])
				ELSE ISNULL([translated_value], [value])
			END [value], 
			[value_type]
		FROM 
			[#key_value_pairs]
		WHERE 
			[kvp_type] = N'key'
	), 
	[keys] AS (
		SELECT 
			[sort_id],
			[kvp_type],
			COUNT(*) OVER (PARTITION BY [row_number], [json_row_id]) [kvp_count], 
			ROW_NUMBER() OVER (PARTITION BY [row_number], [json_row_id] ORDER BY [sort_id]) [current_kvp],
			[row_number],
			[json_row_id],
			[column],
			[value],
			[value_type]
		FROM 
			core
	)

	SELECT 
		[sort_id],
		[row_number],
		[json_row_id],
		[kvp_type],
		[kvp_count],
		[current_kvp],
		[column],
		[value],
		[value_type]
	INTO 
		#translated_kvps
	FROM 
		keys;
		
	WITH core AS ( 
		SELECT 
			ROW_NUMBER() OVER (ORDER BY [kvp_id]) [sort_id],
			[kvp_type], 
			[row_number], 
			[json_row_id],
			[table], 
			ISNULL([translated_column], [column]) [column], 
			CASE 
				WHEN [value_type] = 5 THEN ISNULL([translated_update_value], [value])
				ELSE ISNULL([translated_value], [value])
			END [value], 
			[value_type]
		FROM 
			[#key_value_pairs]
		WHERE 
			[kvp_type] = N'detail'

	), 
	[details] AS (
		SELECT 
			[sort_id],
			[kvp_type],
			COUNT(*) OVER (PARTITION BY [row_number], [json_row_id]) [kvp_count], 
			ROW_NUMBER() OVER (PARTITION BY [row_number], [json_row_id] ORDER BY [sort_id]) [current_kvp],
			[row_number],
			[json_row_id],
			[column],
			[value],
			[value_type]
		FROM 
			core
	)

	INSERT INTO [#translated_kvps] (
		[sort_id],
		[row_number],
		[json_row_id],
		[kvp_type],
		[kvp_count],
		[current_kvp],
		[column],
		[value],
		[value_type]
	)
	SELECT 
		[sort_id],
		[row_number],
		[json_row_id],
		[kvp_type],
		[kvp_count],
		[current_kvp],
		[column],
		[value],
		[value_type]
	FROM 
		[details];

	-- collapse multi-row results back down to a single 'set'/row of results:
	IF EXISTS (SELECT NULL FROM [#raw_data] WHERE [row_count] > 1) BEGIN 

		WITH [flattened] AS ( 
			SELECT 
				x.[row_number], 
				x.[json_row_id], 
				x.[kvp_type],
				x.[kvp_count], 
				x.[current_kvp], 
				x.[column], 
				x.[value], 
				x.[value_type], 
				x.[sort_id]		
			FROM 
				[#translated_kvps] x
				INNER JOIN [#raw_data] r ON [x].[row_number] = [r].[row_number]
			WHERE 
				r.[row_count] > 1
		), 
		[keys] AS ( 
			SELECT 
				*
			FROM 
				[flattened]
			WHERE 
				[flattened].[kvp_type] = N'key'

		), 
		[details] AS ( 
			SELECT 
				*
			FROM 
				[flattened]
			WHERE 
				[flattened].[kvp_type] = N'detail'
		),
		[collapsed] AS (
			SELECT 
				x.[row_number], 
				f.[json_row_id], 
				(
					SELECT
						STRING_AGG(
							N'"' + [k].[column] + N'":' + 
							CASE 
								WHEN [k].[value_type] = 1 THEN N'"' + [k].[value] + N'"'
								ELSE [k].[value]
							END + 
							CASE 
								WHEN [k].[current_kvp] = [k].[kvp_count] THEN N''
								ELSE N','
							END
						, '') WITHIN GROUP (ORDER BY [k].[json_row_id], [k].[current_kvp], [k].[sort_id])
					FROM 
						[keys] [k]
					WHERE 
						[x].[row_number] = [k].[row_number] 
						AND [f].[json_row_id] = [k].[json_row_id]
				) [key_data], 
				(
					SELECT 
						STRING_AGG(
							N'"' + [d].[column] + N'":' + 
							CASE 
								WHEN [d].[value_type] = 1 THEN N'"' + [d].[value] + N'"'
								ELSE [d].[value]
							END + 
							CASE 
								WHEN [d].[current_kvp] = [d].[kvp_count] THEN N''
								ELSE N','
							END
						, '') WITHIN GROUP (ORDER BY [d].[json_row_id], [d].[current_kvp], [d].[sort_id])
					FROM 
						[details] [d] 
					WHERE 
						[x].[row_number] = [d].[row_number] 
						AND [f].[json_row_id] = [d].[json_row_id]
				) [detail_data]
			FROM 
				[#raw_data] [x]
				INNER JOIN [flattened] f ON [x].[row_number] = f.[row_number]
			GROUP BY 
				[x].[row_number], f.[json_row_id]
		),
		[serialized] AS ( 
			SELECT 
				[x].[row_number], 
				N'[' + (
					SELECT 
						STRING_AGG(N'{"key": [{' + [c].[key_data] + N'}],"detail":[{' + [c].[detail_data] + N'}]}', ',') WITHIN GROUP (ORDER BY [c].[json_row_id])
						FROM [collapsed] [c] WHERE c.[row_number] = x.[row_number]
				) + N']' [serialized]
			FROM 
				[#raw_data] [x] 
			WHERE 
				[x].[row_count] > 1
		)

		UPDATE [r] 
		SET 
			[r].[translated_multi_row] = [s].[serialized]
		FROM 
			[#raw_data] [r] 
			INNER JOIN [serialized] [s] ON [r].[row_number] = [s].[row_number]	
		WHERE 
			[r].[row_count] > 1
	END;

	-- Serialize KVPs (ordered by row_number) down to JSON: 
	WITH [row_numbers] AS (
		SELECT 
			[row_number] 
		FROM 
			[#raw_data]
		WHERE 
			[row_count] = 1
		GROUP BY 
			[row_number]
	), 
	[keys] AS ( 
		SELECT 
			[x].[row_number], 
			(
				SELECT 
					STRING_AGG(
						N'"' + [x2].[column] + N'":' +
						CASE 
							WHEN [x2].[value_type] = 1 THEN N'"' + [x2].[value] + N'"'
							ELSE [x2].[value]
						END + 
						CASE 
							WHEN [x2].[current_kvp] = [x2].[kvp_count] THEN N''
							ELSE N','
						END
					, '') WITHIN GROUP (ORDER BY [x2].[json_row_id], [x2].[current_kvp], [x2].[sort_id])
				FROM 
					[#translated_kvps] x2 WHERE [x].[row_number] = [x2].[row_number] AND [x2].[kvp_type] = N'key'
			) [key_data]
		FROM 
			[row_numbers] x

	), 
	[details] AS (
		SELECT 
			[x].[row_number], 
			( 
				SELECT 
					STRING_AGG(
						N'"' + [x2].[column] + N'":' +
						CASE 
							WHEN [x2].[value_type] = 1 THEN N'"' + [x2].[value] + N'"'
							ELSE [x2].[value]
						END + 
						CASE 
							WHEN [x2].[current_kvp] = [x2].[kvp_count] THEN N''
							ELSE N','
						END
					, '') WITHIN GROUP (ORDER BY [x2].[json_row_id], [x2].[current_kvp], [x2].[sort_id])

				FROM 
					[#translated_kvps] x2 WHERE [x].[row_number] = [x2].[row_number] AND [x2].[kvp_type] = N'detail'
			) [detail_data]
		FROM 
			[row_numbers] x
	)

	UPDATE [x] 
	SET 
		[x].[translated_change_key] = k.[key_data], 
		[x].[translated_change_detail] = d.[detail_data]
	FROM 
		[#raw_data] x 
		INNER JOIN [keys] k ON [x].[row_number] = [k].[row_number]
		INNER JOIN [details] d ON [x].[row_number] = [d].[row_number]
	WHERE 
		x.row_count = 1;

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
		CASE 
			WHEN [translated_change_key] IS NOT NULL THEN N'[{"key":[{' + [translated_change_key] + N'}],"detail":[{' + [translated_change_detail] + N'}]}]'
			WHEN [translated_multi_row] IS NOT NULL THEN [translated_multi_row] -- this and translated_change_key won't ever BOTH be populated (only one OR the other).
			ELSE [change_details]
		END [change_details] 
	FROM 
		[#raw_data]
	ORDER BY 
		[row_number];

	RETURN 0;
GO