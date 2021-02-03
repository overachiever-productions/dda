-- TODO/PICKUP/NEXT: I'm down around lines 450-ish ... where I've got a RETURN 0. 
-- To that point, I've shredded multi-row captures AND translated them as needed. 
-- then, i just need to 'redetect' them... and ... serialize them back down to a SINGLE 'row' of data. 
-- MIGHT make sense to simply add a 'translated_collapsed_rows' column or something stupid/tame like that as an initial attempt?


/*

	EXAMPLE (lame) Signatures:

			EXEC dda.[get_audit_data]
				@StartTime = '2021-01-01 18:55:05',
				@EndTime = '2021-01-30 18:55:05',
				--@TargetUsers = N'',
				--@TargetTables = N'',
				@TransformOutput = 1,
				@FromIndex = 1, 
				@ToIndex = 20;
				--@FromIndex = 4,
				--@ToIndex = 6

			EXEC dda.[get_audit_data]
				@TargetUsers = N'sa, bilbo',
				@TargetTables = N'SortTable,Errors',
				@FromIndex = 1,
				@TransformOutput = 1,
				@ToIndex = 10;



	TODO: 
		move these (comments) OUT of the sproc body and into docs:
			-- Biz Rules: 
			-- @StartTime can be specified without @EndTime (set @EndTime = GETDATE()). 
			-- @EndTime can NOT be specified without @StartTime (we could set @StartTime = MIN(audit_date), but that's just goofy semantics). 
			-- We CAN query without @StartTime/@EndTime IF we have either @TargetUser or @TargetTable (or both). 
			-- @TargetTable or @TargetUser can be queried WITHOUT times. 
			-- In short: there ALWAYS has to be at LEAST 1x WHERE clause/predicate - but more are always welcome.

*/

DROP PROC IF EXISTS dda.[get_audit_data];
GO

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
		[audit_id],
		[timestamp],
		[schema],
		[table],
		[user],
		[operation],
		[row_count],
		[audit] [change_details]
	FROM 
		[dda].[audits]
	WHERE 
		{TimeFilters}
		{Users}
		{Tables}
) 
SELECT 
	[row_number],
	(SELECT COUNT(*) FROM [total]) [total_rows],
	[audit_id],
	[timestamp],
	[schema] + N''.'' + [table] [table],
	[user],
	[operation],
	[row_count],
	[change_details]
FROM 
	total 
WHERE 
	[total].[row_number] >= @FromIndex AND [total].[row_number] <= @ToIndex;
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
		[row_count] int NOT NULL,
		[change_details] nvarchar(max) NULL, 
		[translated_change_key] nvarchar(MAX) NULL, 
		[translated_change_detail] nvarchar(MAX) NULL, 
		[translated_multi_row] nvarchar(MAX) NULL
	);

	INSERT INTO [#raw_data] (
		[row_number],
		[total_rows],
		[audit_id],
		[timestamp],
		[table],
		[user],
		[operation_type],
		[row_count],
		[change_details]
	)
	EXEC sp_executesql 
		@coreQuery, 
		N'@FromIndex int, @ToIndex int', 
		@FromIndex = @FromIndex, 
		@ToIndex = @ToIndex;
	
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
		-- TODO: hmm. how can i grab the column-order in multi-column key definitions - or, for that matter, 'column' order in the "detail" section when it's shredded?
		[table] sysname NOT NULL, 
		[column] sysname NOT NULL, 
		[translated_column] sysname NULL, 
		[value] nvarchar(MAX) NULL, -- TODO: should I allow nulls here? Or, more importantly: how to handle NULLs here? they may be <NULL> or something 'odd' from JSON (i.e., type 0).
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
		
		-- PERF: 2x passes here, one for $.key and one for $.detail feels cheap/lame. 
		--		should be able to consolidate that down to a single pass with some conditional logic for where to 'shove' the elements (i.e., what to assign for #key_value_pairs.kvp_type)

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

-- TODO: multi-row results ... 
--		a. 2x existing KVP inserts will throw in a WHERE to EXCLUDE cols with > 1 result. 
--		b. multi-col results will get thrown in as row_number.sub_row_number (or some such convention) as a distinct 2x set of passes (and only run those 2x passes IF #raw_data.row_count has a result with > 1. 
--				AND if the table in question is in ... the list of translation (columns or values) tables.
--		c. throw in a [is_multirow]? or some similar marker into #kvps? 
--			either way, down in the re-serialize (translations) process... do a 'pass' for single-row results, and a distinct pass for multi-row results. 

-- PERF: 
--		in point b., above, I make a note of ONLY running 'shredding' ops for rows (with > 1 row-modified AND) where the table they're from is in the list of translation tables... 
--			might make a lot of sense to do that for the other 2x initial shreds/transforms (keys, values) - i.e., predicate those with instructions to ONLY shred/transform for tables where
--			we're going to have the POSSIBILITY of a match. that's a cleaner approach (less shredding) than current implementation: shred all, then DELETE rows from tables that could NOT be a match.

	UPDATE [#key_value_pairs] 
	SET 
		[from_value] = JSON_VALUE([value], N'$.from'), 
		[to_value] = JSON_VALUE([value], N'$.to')--,
	WHERE 
		ISJSON([value]) = 1 AND [value] LIKE '%from":%"to":%';

	-- Pre-Transform (remove rows from tables that do NOT have any possibility of translations happening):
-- PERF: see perf notes from above - this whole INSERT + DELETE (where not applicable) is great, but a BETTER OPTION IS: INSERT-ONLY-WHERE-APPLICABLE.
	DELETE FROM [#key_value_pairs] 
	WHERE
		[table] COLLATE SQL_Latin1_General_CP1_CI_AS NOT IN (SELECT [table_name] FROM dda.[translation_columns] UNION SELECT [table_name] FROM dda.[translation_values]);

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