/*

	TODO: 
		current automation around deployment + updates of dynamic triggers is hard-coded/kludgey around exact
		format/specification of the "FOR INSERT, UPDATE, DELETE" text in the following trigger definition. 
			i.e., changing whitespace can/could/would-probably break 'stuff'. 

			-- example of dump syntax.
			[
				{
					"key": [{}],
					"detail": [{}],
					"dump": [
						{
							"deleted": [
								{
									"PKColumn": 35,
									"AnotherColumn": 77.4, 
									"ThirdColumn": "nnnnnnn"
								},
								{
									"PKColumn": 36,
									"AnotherColumn": 99.2,
									"ThirdColumn": "mmmmmmm"
								}
							],
							"inserted": [
								{
									"PKColumn": 135,
									"AnotherColumn": 177.4,
									"ThirdColumn": "xxxx"
								},
								{
									"PKColumn": 236,
									"AnotherColumn": 299.2,
									"ThirdColumn": "yyyyy"
								}
							]
						}
					]
				}
			]


*/
DROP TRIGGER IF EXISTS [dda].[dynamic_data_auditing_trigger_template];
GO

CREATE TRIGGER [dda].[dynamic_data_auditing_trigger_template] ON [dda].[trigger_host] FOR INSERT, UPDATE, DELETE 
AS 
	-- IF NOCOUNT IS _OFF_ (i.e., echoing rowcounts), disable it for the duration of this trigger (to avoid 'side effects' with output messages):
	DECLARE @nocount sysname = N'ON';  
	IF @@OPTIONS & 512 < 512 BEGIN 
		SET @nocount = N'OFF'; 
		SET NOCOUNT ON;
	END; 

	-- {copyright}

	DECLARE @context varbinary(128) = ISNULL(CONTEXT_INFO(), 0x0);
	IF @context = 0x999090000000000000009999 BEGIN -- set to a random/unique value at deployment
		PRINT 'Dynamic Data Auditing Trigger bypassed.';
		GOTO Cleanup; 
	END;

	DECLARE @tableName sysname, @schemaName sysname;
	SELECT 
		@schemaName = SCHEMA_NAME([schema_id]),
		@tableName = [name]
	FROM 
		sys.objects 
	WHERE 
		[object_id] = (SELECT [parent_object_id] FROM sys.[objects] WHERE [object_id] = @@PROCID);

	DECLARE @auditedTable sysname = QUOTENAME(@schemaName) + N'.' + QUOTENAME(@tableName);
	DECLARE @currentUser sysname = ORIGINAL_LOGIN();   -- persists across context changes/impersonation.
	DECLARE @auditTimeStamp datetime = GETDATE();  -- all audit info always stored at SERVER time. 
	DECLARE @rowCount int = -1;
	DECLARE @txID int = CAST(RIGHT(CAST(CURRENT_TRANSACTION_ID() AS sysname), 9) AS int);

	-- Determine Operation Type: INSERT, UPDATE, or DELETE: 
	DECLARE @operationType sysname; 
	SELECT 
		@operationType = CASE 
			WHEN EXISTS(SELECT NULL FROM INSERTED) AND EXISTS(SELECT NULL FROM DELETED) THEN N'UPDATE'
			WHEN EXISTS(SELECT NULL FROM INSERTED) THEN N'INSERT'
			ELSE N'DELETE'
		END;

	IF UPPER(@operationType) IN (N'INSERT', N'UPDATE') BEGIN
		SELECT NEWID() [dda_trigger_id], * INTO #temp_inserted FROM inserted;
		SELECT @rowCount = @@ROWCOUNT;
	END;
	
	IF UPPER(@operationType) IN (N'DELETE', N'UPDATE') BEGIN
		SELECT NEWID() [dda_trigger_id], * INTO #temp_deleted FROM deleted;
		SELECT @rowCount = ISNULL(NULLIF(@rowCount, -1), @@ROWCOUNT);
	END;

	IF @rowCount < 1 BEGIN 
		GOTO Cleanup; -- nothing to document/audit - bail:
	END;

	DECLARE @template nvarchar(MAX) = N'SELECT @json = (SELECT 
		(SELECT {key_columns} FROM {key_from_and_where} FOR JSON PATH, INCLUDE_NULL_VALUES) [key], 
		(SELECT {detail_columns} FROM {detail_from_and_where} FOR JSON PATH, INCLUDE_NULL_VALUES) [detail]
	FROM 
		{FROM_CLAUSE}
	FOR JSON PATH
);'; 

	DECLARE @sql nvarchar(MAX) = @template;

	DECLARE @pkColumns nvarchar(MAX) = NULL;
	EXEC dda.[extract_key_columns] 
		@TargetSchema = @schemaName,
		@TargetTable = @tableName, 
		@Output = @pkColumns OUTPUT;

	IF NULLIF(@pkColumns, N'') IS NULL BEGIN 
		RAISERROR('Data Auditing Exception - No Primary Key or suitable surrogate defined against table [%s].[%s].', 16, 1, @schemaName, @tableName);
		GOTO Cleanup;
	END;

	DECLARE @keys nvarchar(MAX) = N'';
	DECLARE @columnNames nvarchar(MAX) = N'';
	DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10); 
	DECLARE @tab nchar(1) = NCHAR(9);

	DECLARE @json nvarchar(MAX) = NULL;  -- can/will be set to a "dump" in UPDATEs if multi-row UPDATE of PKs happens.

	-- INSERT/DELETE: grab everything.
	IF UPPER(@operationType) IN (N'INSERT', N'DELETE') BEGIN 
		DECLARE @tempTableName sysname = N'tempdb..#temp_inserted';
		DECLARE @alias sysname = N'i2';
		DECLARE @fromAndWhere nvarchar(MAX) = N'[#temp_inserted] [i2] WHERE [i].[dda_trigger_id] = [i2].[dda_trigger_id]';

		IF UPPER(@operationType) = N'DELETE' BEGIN 
			SELECT 
				@tempTableName = N'tempdb..#temp_deleted',
				@alias = N'd2',
				@fromAndWhere = N'[#temp_deleted] [d2] WHERE [d].[dda_trigger_id] = [d2].[dda_trigger_id]';
		END;

		-- Explicitly Name/Define keys for extraction:
		SELECT
			@keys = @keys + CASE WHEN @operationType = N'INSERT' THEN N'[i2].' ELSE N'[d2].' END + QUOTENAME([result]) + N','
		FROM 
			dda.[split_string](@pkColumns, N',', 1) 
		ORDER BY 
			row_id;

		SELECT 
			@columnNames = @columnNames + QUOTENAME(@alias) + N'.' + QUOTENAME([name]) + N','
		FROM 
			tempdb.sys.columns 
		WHERE 
			[object_id] = OBJECT_ID(@tempTableName)
			AND [name] <> N'dda_trigger_id'
		ORDER BY 
			[column_id];
		
		SELECT 
			@columnNames = LEFT(@columnNames, LEN(@columnNames) - 1),
			@keys = LEFT(@keys, LEN(@keys) -1);

		SET @sql = REPLACE(@sql, N'{FROM_CLAUSE}', CASE WHEN @operationType = N'INSERT' THEN N'[#temp_inserted] [i]' ELSE N'[#temp_deleted] [d]' END);
		
		SET @sql = REPLACE(@sql, N'{key_columns}', @keys);
		SET @sql = REPLACE(@sql, N'{key_from_and_where}', @fromAndWhere);

		SET @sql = REPLACE(@sql, N'{detail_columns}', @columnNames);
		SET @sql = REPLACE(@sql, N'{detail_from_and_where}', @fromAndWhere);
	END;
	
	-- UPDATE: use changeMap to grab modified columns only:
	IF UPPER(@operationType) = N'UPDATE' BEGIN 

		DECLARE @changeMap varbinary(1024) = (SELECT COLUMNS_UPDATED());
		DECLARE @joinKeys nvarchar(MAX) = N'';
		DECLARE @rawKeys nvarchar(MAX) = N''
		DECLARE @rawColumnNames nvarchar(MAX) = N'';
		DECLARE @keyUpdate bit = 0;
		
		SELECT
			@keys = @keys +  N'[i2].' + QUOTENAME([result]) + N',', 
			@joinKeys = @joinKeys + N'[i2].' + QUOTENAME([result]) + N' = [d].' + QUOTENAME([result]) + N' AND ', 
			@rawKeys = @rawKeys + QUOTENAME([result]) + N','
 		FROM 
			dda.[split_string](@pkColumns, N',', 1) 
		ORDER BY 
			row_id;

		SET @keys = LEFT(@keys, LEN(@keys) - 1);

		SELECT
			@columnNames = @columnNames + N'[d].' + QUOTENAME([column_name]) + N' [' + [column_name] + N'.from], ' + @crlf + @tab + @tab + @tab + N'[i2].' + QUOTENAME([column_name]) + N' [' + [column_name] + N'.to], ',
			@rawColumnNames = @rawColumnNames + QUOTENAME([column_name]) + N','
		FROM 
			dda.[translate_modified_columns](@auditedTable, @changeMap)
		WHERE 
			[modified] = 1 
		ORDER BY 
			[column_id]; 

		SELECT 
			@keys = LEFT(@keys, LEN(@keys)), 
			@rawKeys = LEFT(@rawKeys, LEN(@rawKeys) - 1),
			@joinKeys = LEFT(@joinKeys, LEN(@joinKeys) - 4), 
			@columnNames = LEFT(@columnNames, LEN(@columnNames) - 1), 
			@rawColumnNames = LEFT(@rawColumnNames, LEN(@rawColumnNames) - 1);

		DECLARE @from nvarchar(MAX) = N'#temp_deleted d ' + @crlf + @tab + @tab + N'INNER JOIN #temp_inserted i ON ';

		DECLARE @join nvarchar(MAX) = N'';
		SELECT
			@join = @join + N'[d].' + QUOTENAME([result]) + N' = [i].' + QUOTENAME([result]) + N' AND ' 
		FROM 
			dda.[split_string](@pkColumns, N',', 1) 
		ORDER BY 
			row_id;

		IF EXISTS( 
			SELECT NULL FROM dda.[split_string](@rawColumnNames, N',', 1)
			WHERE [result] IN (SELECT [result] FROM dda.[split_string](@rawKeys, N',', 1))
		) SET @keyUpdate = 1;

		IF @keyUpdate = 1 BEGIN 

			IF @rowCount = 1 BEGIN
				-- simulate/create a pseudo-secondary-key by setting 'row_id' for both 'tables' to 1 (since there's only a single row).
				UPDATE [#temp_inserted] SET [dda_trigger_id] = (SELECT TOP (1) [dda_trigger_id] FROM [#temp_deleted]);
				SET @joinKeys = N'[i2].[dda_trigger_id] = [d].[dda_trigger_id] '
			  END;
			ELSE BEGIN 
				-- Either use a secondary_key, or we HAVE to dump #deleted and #inserted contents vs normal row-by-row capture:
				DECLARE @secondaryKeys nvarchar(260);
				SELECT @secondaryKeys = [serialized_secondary_columns] FROM [dda].[secondary_keys] WHERE [schema] = @schemaName AND [table] = @tableName;

				IF @secondaryKeys IS NOT NULL BEGIN 

						SET @joinKeys = N'';
						SELECT 
							@joinKeys = @joinKeys + N'[i2].' + QUOTENAME([result]) + N' = [d].' + QUOTENAME([result]) + N', '
						FROM 
							dda.[split_string](@secondaryKeys, N',', 1)
						ORDER BY 
							[row_id];

						SET @joinKeys = LEFT(@joinKeys, LEN(@joinKeys) - 1);
				  END;
				ELSE BEGIN 
					-- vNEXT: 
					--	another, advanced option, before 'having to dump' would be: 1. get all columns in/from the table being modified, 2. exclude those in COLUMNS_UPDATED(), 
					--		3. see if either a) a checksum of those remaining columns or b) one or more? of those columns could be used as a uniqueifier.
					
					-- execute a DUMP - of ALL columns (and all rows). Start by removing dda_trigger_id column (it's no longer useful - and just 'clutters'/confuses output):
					ALTER TABLE [#temp_deleted] DROP COLUMN [dda_trigger_id];
					ALTER TABLE [#temp_inserted] DROP COLUMN [dda_trigger_id];

					SET @json = N'[{"key":[{}],"detail":[{}],"dump":[{"deleted":{deleted},"inserted":{inserted}}]}]';
					SET @json = REPLACE(@json, N'{deleted}', (SELECT * FROM [#temp_deleted] FOR JSON PATH));
					SET @json = REPLACE(@json, N'{inserted}', (SELECT * FROM [#temp_inserted] FOR JSON PATH));

					RAISERROR(N'Dynamic Data Audits Warning:%s%sMulti-row UPDATEs that modify Primary Key values cannot be tracked without a mapping in dda.secondary_keys.%s%sThis operation was allowed, but resulted in a "dump" to dda.audits vs row-by-row change-tracking details.', 8, 1, @crlf, @tab, @crlf, @tab);
				END;
				
			END;
		  END;
		ELSE BEGIN  -- if PK wasn't changed, check for ROTATE.
			DECLARE @isRotate bit = 0;

			DECLARE @rotateSQL nvarchar(MAX) = N'			WITH delete_sums AS (
				SELECT 
					' + @rawKeys + N', 
					CHECKSUM(' + @rawColumnNames + N') [changesum]
				FROM 
					[#temp_deleted]
			), 
			insert_sums AS (
				SELECT
					' + @rawKeys + N', 
					CHECKSUM(' + @rawColumnNames + N') [changesum]
				FROM 
					[#temp_inserted]
			), 
			comparisons AS ( 
				SELECT 
					' + @keys + N',
					CASE WHEN d.changesum = i2.changesum THEN 1 ELSE 0 END [is_rotate]
				FROM 
					[delete_sums] d 
					INNER JOIN [insert_sums] i2 ON ' + @joinKeys + N'
			)

			SELECT @isRotate = CASE WHEN EXISTS (SELECT NULL FROM comparisons WHERE is_rotate = 0) THEN 0 ELSE 1 END;'

			--EXEC [admindb].dbo.[print_long_string] @rotateSQL;
			
			EXEC sp_executesql 
				@rotateSQL, 
				N'@isRotate bit OUTPUT', 
				@isRotate = @isRotate OUTPUT;

			IF @isRotate = 1 SET @operationType = 'ROTATE';
		END;

		SET @sql  = REPLACE(@sql, N'{FROM_CLAUSE}', N'[#temp_inserted] [i]');
		
		SET @sql = REPLACE(@sql, N'{key_columns}', @keys);
		SET @sql = REPLACE(@sql, N'{key_from_and_where}', N'[#temp_inserted] [i2] WHERE [i].[dda_trigger_id] = [i2].[dda_trigger_id]');

		SET @sql = REPLACE(@sql, N'{detail_columns}', @crlf + @tab + @tab + @tab + @columnNames + @crlf + @tab + @tab);
		SET @sql = REPLACE(@sql, N'{detail_from_and_where}', @crlf + @tab + @tab + @tab + N'[#temp_inserted] [i2]' + @crlf + @tab + @tab + @tab + N'INNER JOIN [#temp_deleted] [d] ON ' + @joinKeys + @crlf + @tab + @tab + N' WHERE [i].[dda_trigger_id] = [i2].[dda_trigger_id]');

	END;
	
	IF @json IS NULL BEGIN 
		EXEC sp_executesql 
			@sql, 
			N'@json nvarchar(MAX) OUTPUT', 
			@json = @json OUTPUT;
	END;

	INSERT INTO [dda].[audits] (
		[timestamp],
		[schema],
		[table],
		[user],
		[operation],
		[transaction_id],
		[row_count],
		[audit]
	)
	VALUES	(
		@auditTimeStamp, 
		@schemaName, 
		@tableName, 
		@currentUser,
		@operationType, 
		@txID,
		@rowCount,
		@json
	);

Cleanup:
	IF @nocount = N'OFF' BEGIN
		SET NOCOUNT OFF;
	END;
GO		

EXEC [sys].[sp_addextendedproperty]
	@name = N'DDATrigger',
	@value = N'true',
	@level0type = 'SCHEMA',
	@level0name = N'dda',
	@level1type = 'TABLE',
	@level1name = N'trigger_host', 
	@level2type = N'TRIGGER', 
	@level2name = N'dynamic_data_auditing_trigger_template'
GO