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
				@TargetTables = N'SortTable,Errors',
				@TransformOutput = 1,
				@FromIndex = 20,
				@ToIndex = 40;

*/

DROP PROC IF EXISTS dda.[get_audit_data];
GO

--## NOTE: Conditional Build (i.e., defaults to SQL Server 2016 version (XML-concat vs STRING_AGG()), but ALTERs to STRING_CONCAT on 2017+ instances).

CREATE PROC dda.[get_audit_data]
	@StartTime					datetime		= NULL, 
	@EndTime					datetime		= NULL, 
	@TargetUsers				nvarchar(MAX)	= NULL, 
	@TargetTables				nvarchar(MAX)	= NULL, 
	@TransformOutput			bit				= 1,
	@FromIndex					int				= 1, 
	@ToIndex					int				= 100
AS
    SET NOCOUNT ON; 

	-- {copyright}

	SET @TargetUsers = NULLIF(@TargetUsers, N'');
	SET @TargetTables = NULLIF(@TargetTables, N'');		
	SET @TransformOutput = ISNULL(@TransformOutput, 1);

	SET @FromIndex = ISNULL(@FromIndex, 1);
	SET @ToIndex = ISNULL(@ToIndex, 1);

	IF @StartTime IS NOT NULL AND @EndTime IS NULL BEGIN 
		SET @EndTime = DATEADD(MINUTE, 2, GETDATE());
	END;

	IF @EndTime IS NOT NULL AND @StartTime IS NULL BEGIN 
		RAISERROR(N'@StartTime MUST be specified if @EndTime is specified. (@StartTime can be specified without @EndTime - and @EndTime will be set to GETDATE().)', 16, 1);
		RETURN - 10;
	END;

	IF @StartTime IS NULL AND @EndTime IS NULL BEGIN
		IF @TargetUsers IS NULL AND @TargetTables IS NULL BEGIN 
			RAISERROR(N'Queries against Audit data MUST be constrained - either specify @StartTime [+ @EndTIme], or @TargetUsers, or @TargetTables - or a combination of constraints.', 16, 1);
			RETURN -11;
		END;
	END;

	IF @StartTime IS NOT NULL BEGIN 
		IF @StartTime > @EndTime BEGIN
			RAISERROR('@StartTime may not be > @EndTime - please check inputs and try again.', 16, 1);
			RETURN -12;
		END;
	END;

	-- Grab matching rows based upon inputs/constraints:
	DECLARE @coreQuery nvarchar(MAX) = N'WITH total AS (
	SELECT 
		ROW_NUMBER() OVER (ORDER BY [timestamp]) [row_number],
		[audit_id]
	FROM 
		[dda].[audits]
	WHERE 
		{TimeFilters}
		{Users}
		{Tables}
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
	DECLARE @predicated bit = 0;

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
		
		IF @predicated = 1 SET @users = N'AND ' + @users;
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
		
		IF @predicated = 1 SET @tables = N'AND ' + @tables;
	END;

	SET @coreQuery = REPLACE(@coreQuery, N'{TimeFilters}', @timeFilters);
	SET @coreQuery = REPLACE(@coreQuery, N'{Users}', @users);
	SET @coreQuery = REPLACE(@coreQuery, N'{Tables}', @tables);
	
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
		[operation_type] char(9) NOT NULL,
		[transaction_id] int NOT NULL,
		[row_count] int NOT NULL,
		[change_details] nvarchar(max) NULL, 
		[translated_change_key] nvarchar(MAX) NULL, 
		[translated_change_detail] nvarchar(MAX) NULL, 
		[translated_multi_row] nvarchar(MAX) NULL
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
		[translated_value_type] int NULL,
		[from_value] nvarchar(MAX) NULL, 
		[translated_from_value] sysname NULL, 
		[translated_from_value_type] int NULL,
		[to_value] sysname NULL, 
		[translated_to_value] sysname NULL, 
		[translated_to_value_type] int NULL,
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

	-- Pre-Transform (remove rows from tables that do NOT have any possibility of translations happening):
-- DDA-39: Bug/Busted:
	--DELETE FROM [#key_value_pairs] 
	--WHERE
	--	[table] COLLATE SQL_Latin1_General_CP1_CI_AS NOT IN (SELECT [table_name] FROM dda.[translation_columns] UNION SELECT [table_name] FROM dda.[translation_values]);

	-- Stage Translations (start with Columns, then do scalar (INSERT/DELETE values), then do from-to (UPDATE) values:
	UPDATE x 
	SET 
		x.[translated_column] = c.[translated_name], 
		x.[translated_value] = v.[translation_value], 
		x.[translated_value_type] = v.[translation_value_type]
	FROM 
		[#key_value_pairs] x
		LEFT OUTER JOIN dda.[translation_columns] c ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = c.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = c.[column_name]
		LEFT OUTER JOIN dda.[translation_values] v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name] 
			AND x.[value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[key_value] COLLATE SQL_Latin1_General_CP1_CI_AS
			AND x.[value] NOT LIKE N'{"from":%"to":%';

	-- Stage from/to value translations:
	UPDATE x 
	SET
		x.[translated_from_value] = v.[translation_value], 
		x.[translated_from_value_type] = v.[translation_value_type]
	FROM 
		[#key_value_pairs] x 
		LEFT OUTER JOIN dda.[translation_values] v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name] 
			AND x.[from_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[key_value] COLLATE SQL_Latin1_General_CP1_CI_AS
	WHERE 
		[from_value] IS NOT NULL; -- only bother executing UPDATEs vs FROM/TO (UPDATE) values.

	UPDATE x 
	SET
		x.[translated_to_value] = v.[translation_value], 
		x.[translated_to_value_type] = v.[translation_value_type]
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
				WHEN [translated_from_value_type] = 1 THEN N'"' + ISNULL([translated_from_value], [from_value]) + N'"' 
				ELSE ISNULL([translated_from_value], [from_value])
			END + N', "to":' + CASE 
				WHEN [translated_to_value_type] = 1 THEN N'"' + ISNULL([translated_to_value], [to_value]) + N'"'
				ELSE + ISNULL([translated_to_value], [to_value])
			END + N'}'
	WHERE 
		[translated_from_value] IS NOT NULL 
		OR 
		[translated_to_value] IS NOT NULL;

-- PERF / TODO:
	-- Remove any audited rows where columns/values translations were POSSIBLE, but did not apply at all to ANY of the audit-data captured: 
-- PERF: might make sense to move this up above the previous UPDATE against KVP... as well? Or does it need to logically stay here? 
-- TODO: test this against a 'wide' table - I've only been testing narrow tables to this point... 
-- ACTUALLY, these aren't quite working... i.e., need to revisit either pre-exclusions or post exclusions... 
--	DELETE FROM [#key_value_pairs] 
--	WHERE 
--		[kvp_type] = N'key'
--		AND [row_number] IN (
--			SELECT [row_number] FROM [#key_value_pairs] 
--			WHERE 
--				[translated_column] IS NULL 
--				AND [translated_value] IS NULL 
--				AND [translated_update_value] IS NULL 
--				AND [kvp_type] = N'key'
--		);
---- PERF: also, if I don't 'pre-exclude' these... then 2x passes here is crappy.
--	DELETE FROM [#key_value_pairs] 
--	WHERE 
--		[kvp_type] = N'detail'
--		AND [row_number] IN (
--			SELECT [row_number] FROM [#key_value_pairs] 
--			WHERE 
--				[translated_column] IS NULL 
--				AND [translated_value] IS NULL 
--				AND [translated_update_value] IS NULL 
--				AND [kvp_type] = N'detail'
--		);

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
			CASE 
				WHEN [value_type] = 5 THEN 5 
				ELSE ISNULL([translated_value_type], [value_type]) 
			END [value_type]
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
			CASE 
				WHEN [value_type] = 5 THEN 5 
				ELSE ISNULL([translated_value_type], [value_type]) 
			END [value_type]
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
				x.[sort_id]		-- not currently used, but will/should be
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
				COALESCE(STUFF(
					(
						SELECT 
							N',' + -- always include (for STUFF() call) - vs conditional include with STRING_AGG()). 
							N'"' + [k].[column] + N'":' + 
							CASE 
								WHEN [k].[value_type] = 2 THEN [k].[value]
								ELSE N'"' + [k].[value] + N'"'
							END  
						FROM 
							[keys] [k]
						WHERE 
							[x].[row_number] = [k].[row_number] 
							AND [f].[json_row_id] = [k].[json_row_id]
						FOR XML PATH('')
					)
				, 1, 1, N''), N'') [key_data],
				COALESCE(STUFF(
					(
						SELECT
							N',' + 
							N'"' + [d].[column] + N'":' + 
							CASE 
								WHEN [d].[value_type] IN (2,5) THEN [d].[value]
								ELSE N'"' + [d].[value] + N'"'
							END
						FROM 
							[details] [d] 
						WHERE 
							[x].[row_number] = [d].[row_number] 
							AND [f].[json_row_id] = [d].[json_row_id]							
						FOR XML PATH('')
					)
				, 1, 1, N''), N'') [detail_data]
			FROM 
				[#raw_data] [x]
				INNER JOIN [flattened] f ON [x].[row_number] = f.[row_number]
			GROUP BY 
				[x].[row_number], f.[json_row_id]
		), 
		[serialized] AS ( 
			SELECT 
				[x].[row_number], 
				N'[' + COALESCE(STUFF(
					(
						SELECT 
							N',' + 
							N'{"key": [{' + [c].[key_data] + N'}],"detail":[{' + [c].[detail_data] + N'}]}'
						FROM 
							[collapsed] [c] WHERE [c].[row_number] = [x].[row_number]
						FOR XML PATH('')
					)
				, 1, 1, N''), N'') + N']' [serialized]

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
			COALESCE(STUFF(
				(
					SELECT 
						N',' + 
						N'"' + [x2].[column] + N'":' +
						CASE 
							WHEN [x2].[value_type] = 2 THEN [x2].[value] 
							ELSE N'"' + [x2].[value] + N'"'
						END 
					FROM 
						[#translated_kvps] x2 WHERE [x].[row_number] = [x2].[row_number] AND [x2].[kvp_type] = N'key'
					FOR XML PATH('')
					
				)
			, 1, 1, N''), N'') [key_data]

		FROM 
			[row_numbers] x

	), 
	[details] AS (
		SELECT 
			[x].[row_number], 
			COALESCE(STUFF(
				(
					SELECT 
						N',' + 
						N'"' + [x2].[column] + N'":' +
						CASE 
							WHEN [x2].[value_type] IN (2, 5) THEN [x2].[value]   -- if it's a number or json/etc... just use the RAW value
							ELSE N'"' + [x2].[value] + N'"'
						END
					FROM 
						[#translated_kvps] x2 WHERE [x].[row_number] = [x2].[row_number] AND [x2].[kvp_type] = N'detail'
					FOR XML PATH('')
				)
			, 1, 1, N''), N'') [detail_data]
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
	@TransformOutput			bit				= 1,
	@FromIndex					int				= 1, 
	@ToIndex					int				= 100
AS
    SET NOCOUNT ON; 

	-- {copyright}

	SET @TargetUsers = NULLIF(@TargetUsers, N'');
	SET @TargetTables = NULLIF(@TargetTables, N'');		
	SET @TransformOutput = ISNULL(@TransformOutput, 1);

	SET @FromIndex = ISNULL(@FromIndex, 1);
	SET @ToIndex = ISNULL(@ToIndex, 1);

	IF @StartTime IS NOT NULL AND @EndTime IS NULL BEGIN 
		SET @EndTime = DATEADD(MINUTE, 2, GETDATE());
	END;

	IF @EndTime IS NOT NULL AND @StartTime IS NULL BEGIN 
		RAISERROR(N'@StartTime MUST be specified if @EndTime is specified. (@StartTime can be specified without @EndTime - and @EndTime will be set to GETDATE().)', 16, 1);
		RETURN - 10;
	END;

	IF @StartTime IS NULL AND @EndTime IS NULL BEGIN
		IF @TargetUsers IS NULL AND @TargetTables IS NULL BEGIN 
			RAISERROR(N'Queries against Audit data MUST be constrained - either specify @StartTime [+ @EndTIme], or @TargetUsers, or @TargetTables - or a combination of constraints.', 16, 1);
			RETURN -11;
		END;
	END;

	IF @StartTime IS NOT NULL BEGIN 
		IF @StartTime > @EndTime BEGIN
			RAISERROR('@StartTime may not be > @EndTime - please check inputs and try again.', 16, 1);
			RETURN -12;
		END;
	END;

	-- Grab matching rows based upon inputs/constraints:
	DECLARE @coreQuery nvarchar(MAX) = N'WITH total AS (
	SELECT 
		ROW_NUMBER() OVER (ORDER BY [timestamp]) [row_number],
		[audit_id]
	FROM 
		[dda].[audits]
	WHERE 
		{TimeFilters}
		{Users}
		{Tables}
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
	DECLARE @predicated bit = 0;

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
		
		IF @predicated = 1 SET @users = N'AND ' + @users;
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
		
		IF @predicated = 1 SET @tables = N'AND ' + @tables;
	END;

	SET @coreQuery = REPLACE(@coreQuery, N'{TimeFilters}', @timeFilters);
	SET @coreQuery = REPLACE(@coreQuery, N'{Users}', @users);
	SET @coreQuery = REPLACE(@coreQuery, N'{Tables}', @tables);
	
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
		[operation_type] char(9) NOT NULL,
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
		[translated_value_type] int NULL,
		[from_value] nvarchar(MAX) NULL, 
		[translated_from_value] sysname NULL, 
		[translated_from_value_type] int NULL,
		[to_value] sysname NULL, 
		[translated_to_value] sysname NULL, 
		[translated_to_value_type] int NULL,
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

	-- Pre-Transform (remove rows from tables that do NOT have any possibility of translations happening):
-- PERF: see perf notes from above - this whole INSERT + DELETE (where not applicable) is great, but a BETTER OPTION IS: INSERT-ONLY-WHERE-APPLICABLE.
-- DDA-39: Bug/Busted:
	--DELETE FROM [#key_value_pairs] 
	--WHERE
	--	[table] COLLATE SQL_Latin1_General_CP1_CI_AS NOT IN (SELECT [table_name] FROM dda.[translation_columns] UNION SELECT [table_name] FROM dda.[translation_values]);

	-- Stage Translations (start with columns, then do scalar (INSERT/DELETE values), then do from-to (UPDATE) values:
	UPDATE x 
	SET 
		x.[translated_column] = c.[translated_name], 
		x.[translated_value] = v.[translation_value], 
		x.[translated_value_type] = v.[translation_value_type]
	FROM 
		[#key_value_pairs] x
		LEFT OUTER JOIN dda.[translation_columns] c ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = c.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = c.[column_name]
		LEFT OUTER JOIN dda.[translation_values] v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name] 
			AND x.[value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[key_value] COLLATE SQL_Latin1_General_CP1_CI_AS
			AND x.[value] NOT LIKE N'{"from":%"to":%';

	-- Stage from/to value translations:
	UPDATE x 
	SET
		x.[translated_from_value] = v.[translation_value], 
		x.[translated_from_value_type] = v.[translation_value_type]
	FROM 
		[#key_value_pairs] x 
		LEFT OUTER JOIN dda.[translation_values] v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name] 
			AND x.[from_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[key_value] COLLATE SQL_Latin1_General_CP1_CI_AS
	WHERE 
		[from_value] IS NOT NULL; -- only bother executing UPDATEs vs FROM/TO (UPDATE) values.

	UPDATE x 
	SET
		x.[translated_to_value] = v.[translation_value], 
		x.[translated_to_value_type] = v.[translation_value_type]
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
				WHEN [translated_from_value_type] = 1 THEN N'"' + ISNULL([translated_from_value], [from_value]) + N'"' 
				ELSE ISNULL([translated_from_value], [from_value])
			END + N', "to":' + CASE 
				WHEN [translated_to_value_type] = 1 THEN N'"' + ISNULL([translated_to_value], [to_value]) + N'"'
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
			CASE 
				WHEN [value_type] = 5 THEN 5 
				ELSE ISNULL([translated_value_type], [value_type]) 
			END [value_type]
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
			CASE 
				WHEN [value_type] = 5 THEN 5 
				ELSE ISNULL([translated_value_type], [value_type]) 
			END [value_type]
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
				x.[sort_id]		-- not currently used, but will/should be
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
								WHEN [k].[value_type] = 2 THEN [k].[value]
								ELSE N'"' + [k].[value] + N'"'
							END + 
							CASE 
								WHEN [k].[current_kvp] = [k].[kvp_count] THEN N''
								ELSE N','
							END
						, '')
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
								WHEN [d].[value_type] IN (2,5) THEN [d].[value]
								ELSE N'"' + [d].[value] + N'"'
							END + 
							CASE 
								WHEN [d].[current_kvp] = [d].[kvp_count] THEN N''
								ELSE N','
							END
						, '')
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
						STRING_AGG(N'{"key": [{' + [c].[key_data] + N'}],"detail":[{' + [c].[detail_data] + N'}]}', ',') 
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
							WHEN [x2].[value_type] = 2 THEN [x2].[value] 
							ELSE N'"' + [x2].[value] + N'"'
						END + 
						CASE 
							WHEN [x2].[current_kvp] = [x2].[kvp_count] THEN N''
							ELSE N','
						END
					, '')
				FROM 
					[#translated_kvps] x2 WHERE [x].[row_number] = [x2].[row_number] AND [x2].[kvp_type] = N'key'
				--ORDER BY 
				--	[x2].[sort_id]
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
							WHEN [x2].[value_type] IN (2, 5) THEN [x2].[value]   -- if it's a number or json/etc... just use the RAW value
							ELSE N'"' + [x2].[value] + N'"'
						END + 
						CASE 
							WHEN [x2].[current_kvp] = [x2].[kvp_count] THEN N''
							ELSE N','
						END
					, '')

				FROM 
					[#translated_kvps] x2 WHERE [x].[row_number] = [x2].[row_number] AND [x2].[kvp_type] = N'detail'
				--ORDER BY 
				--	[x2].[sort_id]
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