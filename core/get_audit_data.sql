/*

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

-- TODO: move these (comments) OUT of the sproc body and into docs:
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
		SET @users = N'[user] = ''' + @TargetUsers + N''' ';
		IF @predicated = 1 SET @users = N'AND ' + @users;

		SET @predicated = 1;
	END;

	IF @TargetTables IS NOT NULL BEGIN
-- TODO: need ... schema + table here... i.e., substitute-in dbo. if schema isn't specified (per table).
		SET @tables = N'[table] = nnnn ';  
		IF @predicated = 1 SET @tables = N'AND ' + @tables;
	END;

	SET @coreQuery = REPLACE(@coreQuery, N'{TimeFilters}', @timeFilters);
	SET @coreQuery = REPLACE(@coreQuery, N'{Users}', @users);
	SET @coreQuery = REPLACE(@coreQuery, N'{Tables}', @tables);
	
	DECLARE @matchedRows int;

	CREATE TABLE #raw_data ( 
		[row_number] int NOT NULL,
		[total_rows] int NOT NULL, 
		[timestamp] datetime NOT NULL,
		[table] sysname NOT NULL,
		[translated_table] sysname NULL,
		[user] sysname NOT NULL,
		[operation_type] char(9) NOT NULL,
		[row_count] int NOT NULL,
		[change_details] nvarchar(max) NULL, 
		[translated_change_key] nvarchar(MAX) NULL, 
		[translated_change_detail] nvarchar(MAX) NULL
	);

	INSERT INTO [#raw_data] (
		[row_number],
		[total_rows],
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
	IF @matchedRows < 1 GOTO Final_Projection;
	IF @TransformOutput <> 1 BEGIN
		
		UPDATE [#raw_data] 
		SET 
			[translated_table] = [table];

		GOTO Final_Projection;
	END;

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
		[table] sysname NOT NULL, 
		[column] sysname NOT NULL, 
		[translated_column] sysname NULL, 
		[value] nvarchar(MAX) NULL, -- TODO: should I allow nulls here? 
		[translated_value] sysname NULL, 
		[from_value] nvarchar(MAX) NULL, 
		[translated_from_value] sysname NULL, 
		[to_value] sysname NULL, 
		[translated_to_value] sysname NULL, 
		[translated_update_value] nvarchar(MAX) NULL
	);

-- TODO: multi-row results ... 
--		a. 2x existing KVP inserts will throw in a WHERE to EXCLUDE cols with > 1 result. 
--		b. multi-col results will get thrown in as row_number.sub_row_number (or some such convention) as a distinct 2x set of passes (and only run those 2x passes IF #raw_data.row_count has a result with > 1. 
--				AND if the table in question is in ... the list of translation (columns or values) tables.
--		c. throw in a [is_multirow]? or some similar marker into #kvps? 
--			either way, down in the re-serialize (translations) process... do a 'pass' for single-row results, and a distinct pass for multi-row results. 
--		d. may need to change the audit_trigger - so that it puts multi-row results into ... multiple 'rows' (so that I have a better 'handle' into the results?). 
---			that said... should be such that an ordinal could/would/should work? (i.e., just need to test that crap out).


-- PERF: 
--		in point b., above, I make a note of ONLY running 'shredding' ops for rows (with > 1 row-modified AND) where the table they're from is in the list of translation tables... 
--			might make a lot of sense to do that for the other 2x initial shreds/transforms (keys, values) - i.e., predicate those with instructions to ONLY shred/transform for tables where
--			we're going to have the POSSIBILITY of a match. that's a cleaner approach (less shredding) than current implementation: shred all, then DELETE rows from tables that could NOT be a match.

	INSERT INTO [#key_value_pairs] (
		[kvp_type],
		[table],
		[row_number],
		[column],
		[value]
	)
	SELECT 
		N'key',
		x.[table], 
		x.[row_number],
		z.[Key] [column], 
		z.[Value] [value]
	FROM 
		[#raw_data] x
-- TODO: pay attention to OPENJASON()'s .type result/property: https://docs.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql?view=sql-server-ver15#return-value 
--		that full-blown shows/tracks data-types - which I could/should be able to use to help 'drive' translations if/as needed. (translation_values COULD end up having a data-type associated - 
--			i.e., lol, translation_value_number, translation_value_string, translation_value_bool, translation_value_date (which... hmm... is 'missing' guess it's just text - 
--					yeah, I'd treat anything other than numbers as ... strings... ) ... but still, strings vs non-strings would be great... 
		OUTER APPLY OPENJSON(JSON_QUERY(x.[change_details], '$[0].key'), '$') z
	WHERE 
		z.[Key] IS NOT NULL 
		AND z.[Value] IS NOT NULL;

	INSERT INTO [#key_value_pairs] (
		[kvp_type],
		[table],
		[row_number],
		[column],
		[value]
	)
	SELECT 
		N'detail',
		x.[table], 
		x.[row_number],
		y.[Key] [column], 
		y.[Value] [value]
	FROM 
		[#raw_data] x 
		CROSS APPLY OPENJSON(JSON_QUERY(x.[change_details], '$[0].detail'), '$') y
	WHERE 
		y.[Key] <> 'row_identifier'
		AND y.[Value] IS NOT NULL;
		
	UPDATE [#key_value_pairs] 
	SET 
		from_value = JSON_VALUE([value], N'$.from'), 
		to_value = JSON_VALUE([value], N'$.to')
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
		x.[translated_value] = v.[translation_value]
	FROM 
		[#key_value_pairs] x
		LEFT OUTER JOIN dda.[translation_columns] c ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = c.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = c.[column_name]
		LEFT OUTER JOIN dda.[translation_values] v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name] 
			AND x.[value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[key_value] COLLATE SQL_Latin1_General_CP1_CI_AS
			AND x.[value] NOT LIKE N'{"from":%"to":%';

	UPDATE x 
	SET
		x.[translated_from_value] = v.[translation_value]
	FROM 
		[#key_value_pairs] x 
		LEFT OUTER JOIN dda.[translation_values] v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name] 
			AND x.[from_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[key_value] COLLATE SQL_Latin1_General_CP1_CI_AS
	WHERE 
		[from_value] IS NOT NULL; -- only bother executing UPDATEs vs FROM/TO (UPDATE) values.

	UPDATE x 
	SET
		x.[translated_to_value] = v.[translation_value]
	FROM 
		[#key_value_pairs] x 
		LEFT OUTER JOIN dda.[translation_values] v ON x.[table] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[table_name] AND x.[column] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[column_name] 
			AND x.[to_value] COLLATE SQL_Latin1_General_CP1_CI_AS = v.[key_value] COLLATE SQL_Latin1_General_CP1_CI_AS
	WHERE 
		[to_value] IS NOT NULL; -- ditto... 

	-- Serialize from/to values (UPDATE summaries) back down to JSON:
	UPDATE [#key_value_pairs] 
	SET 
		[translated_update_value] = N'{"from":"' + ISNULL([translated_from_value], [from_value]) + N'", "to":"' + ISNULL([translated_to_value], [to_value]) + N'"}'
	WHERE 
		[translated_from_value] IS NOT NULL 
		OR 
		[translated_to_value] IS NOT NULL;

	-- Remove any audited rows where columns/values translations were POSSIBLE, but did not apply at all to ANY of the audit-data captured: 
-- PERF: might make sense to move this up above the previous UPDATE against KVP... as well? Or does it need to logically stay here? 
-- TODO: test this against a 'wide' table - I've only been testing narrow tables to this point... 
	DELETE FROM [#key_value_pairs] 
	WHERE 
		[row_number] NOT IN (
			SELECT [row_number] FROM [#key_value_pairs] 
			WHERE 
				[translated_column] IS NOT NULL 
				OR [translated_value] IS NOT NULL 
				OR [translated_update_value] IS NOT NULL 
		);

	-- Collapse translations + non-translations down to a single working set: 
	SELECT 
		[kvp_type], 
		[row_number], 
		[table], 
		ISNULL([translated_column], [column]) [column], 
		CASE 
			WHEN [value] LIKE N'{"from":%"to":%' THEN ISNULL([translated_update_value], [value]) 
			ELSE ISNULL([translated_value], [value])
		END [value]
	INTO 
		#translated_kvps
	FROM 
		[#key_value_pairs];

	CREATE TABLE #translated_data (
		[row_number] int NOT NULL, 
		[operation_type] char(9) NOT NULL,
		[row_count] int NOT NULL,
		[key_data] nvarchar(MAX) NOT NULL, 
		[detail_data] nvarchar(MAX) NOT NULL
	);

	-- Process Translations: 
	DECLARE @currentTranslationTable sysname;
	DECLARE @translationSql nvarchar(MAX);
	DECLARE [walker] CURSOR LOCAL FAST_FORWARD FOR 
	SELECT DISTINCT 
		[table]
	FROM 
		[#key_value_pairs];

	OPEN [walker];
	FETCH NEXT FROM [walker] INTO @currentTranslationTable;
	
	WHILE @@FETCH_STATUS = 0 BEGIN
	
		TRUNCATE TABLE [#translated_data];

		WITH [row_numbers] AS ( 
			SELECT 
				[row_number]
			FROM 
				[#key_value_pairs]
			WHERE 
				[table] = @currentTranslationTable
			GROUP BY 
				[row_number]
		),
		[keys] AS (
			SELECT 
				x.[row_number], 
				(SELECT [column] [key_col], [value] [key_val] FROM [#translated_kvps] x2 WHERE x2.[table] = @currentTranslationTable AND x.[row_number] = x2.[row_number] AND x2.[kvp_type] = N'key' /* ORDER BY xxx here*/ FOR JSON AUTO, WITHOUT_ARRAY_WRAPPER) [key_data]
			FROM 
				[row_numbers] x 
		), 
		[details] AS (

			SELECT 
				x.[row_number],
				(SELECT [column] [detail_col], [value] [detail_val] FROM [#translated_kvps] x2 WHERE x2.[table] = @currentTranslationTable AND x.[row_number] = x2.[row_number] AND x2.[kvp_type] = N'detail' /* ORDER BY xxx here*/ FOR JSON AUTO, WITHOUT_ARRAY_WRAPPER) [detail_data]
			FROM 
				[row_numbers] x
		)

		INSERT INTO [#translated_data] (
			[row_number],
			[operation_type],
			[row_count],
			[key_data],
			[detail_data]
		)
		SELECT 
			[r].[row_number], 
			[x].[operation_type], 
			[x].[row_count],
			[k].[key_data],
			[d].[detail_data]
		FROM 
			[row_numbers] r 
			INNER JOIN [#raw_data] x ON [r].[row_number] = [x].[row_number]
			INNER JOIN keys k ON [r].[row_number] = [k].[row_number] 
			INNER JOIN [details] d ON [r].[row_number] = [d].[row_number];

		-- Keys Translation: 
		WITH [streamlined] AS ( 
			SELECT 
				[row_number], 
				[operation_type], 
				[row_count], 
-- HACK (for now - i.e., need to remove the whole WITHOUT_ARRAY_WRAPPER directives up above...)
				N'[' + [key_data] + N']' [data]
			FROM 
				[#translated_data] 
		), 
		[shredded_keys] AS (
			SELECT 
				s.[row_number], 
				s.[operation_type], 
				s.[row_count],  -- NOT sure this is even needed... but... will have to address when I get to multi-row audit-records.
				ROW_NUMBER() OVER(PARTITION BY s.[row_number] ORDER BY x.[Key], y.[Key]) [attribute_number], 
				COUNT(*) OVER(PARTITION BY s.[row_number]) [attribute_count], 
				y.[Key] [key], 
				y.[Value] [value], 
				y.[Type] [type]
			FROM 
				streamlined s
				CROSS APPLY OPENJSON(JSON_QUERY(s.[data], N'$'), N'$') x 
				CROSS APPLY OPENJSON(x.[Value], N'$') y
		), 
		[serialized_keys] AS ( 

			SELECT 
				[row_number],
				STRING_AGG(
					CASE 
						WHEN [key] = N'key_col' THEN N'"' + [value] + N'":' 
						ELSE 
							CASE 
								WHEN [type] = 2 THEN [value] 
								ELSE N'"' + [value] + N'"'
							END
							+ 
							CASE 
								WHEN [attribute_number] = [attribute_count] THEN N''
								ELSE N','
							END
					END, '') [translated_key]
			FROM 
				[shredded_keys]
			GROUP BY 
				[row_number]
		)

		--SELECT * FROM [shredded_keys];
		UPDATE x 
		SET 
			x.[translated_change_key] = k.[translated_key]
		FROM 
			[#raw_data] x  
			INNER JOIN [serialized_keys] k ON [x].[row_number] = [k].[row_number]
		WHERE 
			x.[translated_change_key] IS NULL;

		-- Details Translation:
		WITH [streamlined] AS ( 
			SELECT 
				[row_number], 
				[operation_type], 
				[row_count], 
-- HACK (for now - i.e., need to remove the whole WITHOUT_ARRAY_WRAPPER directives up above...)
				N'[' + [detail_data] + N']' [data]
			FROM 
				[#translated_data] 
		), 
		[shredded_details] AS (
			SELECT 
				s.[row_number], 
				s.[operation_type], 
				s.[row_count],  -- NOT sure this is even needed... but... will have to address when I get to multi-row audit-records.
				ROW_NUMBER() OVER(PARTITION BY s.[row_number] ORDER BY x.[Key], y.[Key]) [attribute_number], 
				COUNT(*) OVER(PARTITION BY s.[row_number]) [attribute_count], 
				y.[Key] [key], 
				y.[Value] [value], 
				y.[Type] [type]
			FROM 
				streamlined s
				CROSS APPLY OPENJSON(JSON_QUERY(s.[data], N'$'), N'$') x 
				CROSS APPLY OPENJSON(x.[Value], N'$') y
		), 
		[serialized_details] AS (

			SELECT 
				[row_number],
				STRING_AGG(
					CASE 
						 WHEN [key] = N'detail_col' THEN N'"' + [value] + N'":' 
						 ELSE 
							CASE 
								WHEN [operation_type] = N'UPDATE' THEN N'[' + [value] + N']'
								ELSE 
									CASE 
										WHEN [type] = 2 THEN [value]
										ELSE N'"' + [value] + N'"'
									END
							END
							+ 
							CASE 
								WHEN [attribute_number] = [attribute_count] THEN N''
								ELSE N','
							END
					END, '') [translated_detail]
			FROM 
				[shredded_details] 
			GROUP BY 
				[row_number]
		)

		UPDATE x 
		SET 
			x.[translated_change_detail] = d.[translated_detail]
		FROM 
			[#raw_data] x 
			INNER JOIN [serialized_details] d ON [x].[row_number] = [d].[row_number]
		WHERE 
			x.[translated_change_detail] IS NULL;

		FETCH NEXT FROM [walker] INTO @currentTranslationTable;
	END;
	CLOSE [walker];
	DEALLOCATE [walker];

Final_Projection:
	SELECT 
		[row_number],
		[total_rows],
		[timestamp],
		[user],
		[translated_table] [table],
		[operation_type],
		[row_count],
		CASE 
			WHEN [translated_change_key] IS NOT NULL THEN N'[{"key":[' + [translated_change_key] + N'],"detail":[' + [translated_change_detail] + N']}]'
			ELSE [change_details]
		END [change_details] 
	FROM [#raw_data];

	RETURN 0;
GO