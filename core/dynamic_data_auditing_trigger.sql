/*


*/

DECLARE @contextValue sysname = (SELECT CAST(p.[value] AS sysname) FROM sys.[triggers] t INNER JOIN sys.[extended_properties] p ON t.[object_id] = p.[major_id]
WHERE t.[name] = N'dynamic_data_auditing_trigger_template' AND p.[name] = N'DDATrigger - Bypass Value');

IF @contextValue IS NOT NULL BEGIN 
	EXEC sp_set_session_context @key = N'CONTEXT_INFO', @value = @contextValue;
END;

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
	IF @context = 0x999090000000000000009999 BEGIN /* @context is randomized/uniquified during deployment ... */
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
	DECLARE @originalLogin sysname = ORIGINAL_LOGIN();   -- persists across context changes/impersonation.
	DECLARE @currentUser sysname = USER_NAME(); -- current user - if/when impersonated.
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

	--~~ ::CUSTOM LOGIC::start


	--~~ ::CUSTOM LOGIC::end


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

		DECLARE @isRotate bit = 0;
		DECLARE @rotateSQL nvarchar(MAX);
		DECLARE @rotateTestColumnNames nvarchar(MAX) = @rawColumnNames;
		IF(@rotateTestColumnNames NOT LIKE N'%,%') BEGIN
			SET @rotateTestColumnNames = @rotateTestColumnNames + N', ''concat_place_holder''';
		END;

		SET @rotateSQL = N'			WITH delete_sums AS (
			SELECT 
				' + @rawKeys + N', 
				HASHBYTES(''SHA2_512'', CONCAT(' + @rotateTestColumnNames + N')) [changesum]
			FROM 
				[#temp_deleted]
		), 
		insert_sums AS (
			SELECT
				' + @rawKeys + N', 
				HASHBYTES(''SHA2_512'', CONCAT(' + @rotateTestColumnNames + N')) [changesum]
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

		SELECT @isRotate = CASE WHEN EXISTS (SELECT NULL FROM comparisons WHERE is_rotate = 1) THEN 1 ELSE 0 END;'
		
		EXEC sp_executesql 
			@rotateSQL, 
			N'@isRotate bit OUTPUT', 
			@isRotate = @isRotate OUTPUT;

		IF @rowCount = 1 BEGIN 
			/* There are effectively 2 outcomes possible here: a ROTATE, or an UPDATE (only, if the UPDATE includes changes to key columns, we'll fake this back to a normal UPDATE) */
			IF @keyUpdate = 1 BEGIN 
				/* simulate/create a pseudo-secondary-key by setting 'row_id' for both 'tables' to 1 (since there's only a single row).  */
				UPDATE [#temp_inserted] SET [dda_trigger_id] = (SELECT TOP (1) [dda_trigger_id] FROM [#temp_deleted]);
				SET @joinKeys = N'[i2].[dda_trigger_id] = [d].[dda_trigger_id] ';
			END;

			/* at this point, we're 'back' to a normal UPDATE - UNLESS this is a ROTATE: */
			IF @isRotate = 1 SET @operationType = 'ROTATE';

		  END;
		ELSE BEGIN 
			
			IF @keyUpdate = 1 BEGIN /* determine if this is a MUTATE or an UPDATE */
				/* If we have secondary keys defined, we can use those and 'salvage' this as an UPDATE (or ROTATE) */				
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

					SET @operationType = N'MUTATE'; 

					RAISERROR(N'Dynamic Data Audits Warning:%s%sMulti-row UPDATEs that modify Primary Key values cannot be tracked without a mapping in dda.secondary_keys.%s%sThis operation was allowed, but resulted in a "dump" to dda.audits vs row-by-row change-tracking details.', 8, 1, @crlf, @tab, @crlf, @tab);
				END;
			END; 
			
			IF @operationType <> N'MUTATE' BEGIN /* if it's not a MUTATE, it's an UPDATE - unless it's a ROTATE */
				IF @isRotate = 1 SET @operationType = 'ROTATE';
			END;
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
		[original_login],
		[executing_user],
		[operation],
		[transaction_id],
		[row_count],
		[audit]
	)
	VALUES	(
		@auditTimeStamp, 
		@schemaName, 
		@tableName, 
		@originalLogin,
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
	@level2name = N'dynamic_data_auditing_trigger_template';
GO

DECLARE @contextBypass sysname = (SELECT CAST(SESSION_CONTEXT(N'CONTEXT_INFO') AS sysname));

IF @contextBypass IS NULL BEGIN 
	SET @contextBypass = CONVERT(nvarchar(26), CAST(NEWID() AS varbinary(128)), 1);
	PRINT N'Assigning NEW CONTEXT_INFO() value of ' + @contextBypass + N' for trigger bypass functionality.';
  END; 
ELSE BEGIN 
	PRINT N'Assigning Existing CONTEXT_INFO() value of ' + @contextBypass + N' for trigger bypass functionality.';
END;

DECLARE @definition nvarchar(MAX);
SELECT @definition = [definition] FROM sys.[sql_modules] WHERE [object_id] = (SELECT [object_id] FROM sys.[triggers] WHERE [name] = N'dynamic_data_auditing_trigger_template' AND [parent_id] = OBJECT_ID('dda.trigger_host'));
DECLARE @body nvarchar(MAX) = REPLACE(@definition, N'CREATE TRIGGER [dda].[dynamic_data_auditing_trigger_template]', N'ALTER TRIGGER [dda].[dynamic_data_auditing_trigger_template]');
SET @body = REPLACE(@body, N'0x999090000000000000009999', @contextBypass);

EXEC sp_executesql @body;

-- 'mark' the value for future updates/changes:
DECLARE @marker nvarchar(MAX) = N'EXEC [sys].[sp_addextendedproperty]
	@name = N''DDATrigger - Bypass Value'',
	@value = N''' + @contextBypass + N''',
	@level0type = ''SCHEMA'',
	@level0name = N''dda'',
	@level1type = ''TABLE'',
	@level1name = N''trigger_host'', 
	@level2type = N''TRIGGER'', 
	@level2name = N''dynamic_data_auditing_trigger_template''; ';

EXEC sp_executesql @marker;

-- clear session-copntext - for subsequent runs/executions/etc. 
EXEC sp_set_session_context @key = N'CONTEXT_INFO', @value = NULL;
GO