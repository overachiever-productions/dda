/*

	TODO: 
		current automation around deployment + updates of dynamic triggers is hard-coded/kludgey around exact
		format/specification of the "FOR INSERT, UPDATE, DELETE" text in the following trigger definition. 
			i.e., changing whitespace can/could/would-probably break 'stuff'. 

	 vNEXT: 
		Look into detecting non-UPDATING updates i.e., SET x = y, a = b ... as the UPDATE but where x is ALREADY y, and a is ALREADY b 
			(i.e., full or partial removal of 'duplicates'/non-changes is what we're after - i.e., if x and a were only columns in SET of UPDATE and there are no changes, 
				maybe BAIL and don't record this? whereas if it was x OR a that had a change, just record the ONE that changed?


	COMPOSITE KEYS:
		If there's 1x row. it's easy: 
			a. detect that there was a change to the keys (meta-data should make this easy enough and/or check columns_changed vs keys - i.e.,, i've already established both... )
			b. again, if it's a single row - it's just a TOP (1) JOIN or something stupid (i.e., hard-coded SELECT/grab against old/new - the end). 

		If there are > 1 rows modified
			a. dayum. 
			b. unless 
				1. inserted and deleted both 100% get 'populated' in the same order 
				AND
				2. I can somehow ROW_NUMBER() them OUT of those tables in a 100% predictable order... 
					then game over. seriously. 
						
						Assume a table with the following columns:
								ID
								SequenceNumber 

						And values of: 
								1, 1
								1, 2
								1, 3

						And this UPDATE:
							UPDATE myTable SET SequenceNumber = SequenceNumber + 1 WHERE ID = 1; 

								that's 3x rows... changes
									unless i KNOW that 'row 1' of deleted is the SAME as 'row 1' of inserted.. there's no way to glue this stuff together. 
										period. i could try various hashes, various CROSS joins, but ... therey're not going to give me the kinds of results i need. 


							So, the tests I need to determine how inserted/delete behave (and how ROW_NUMBER() OVER() work... ) 
								would be: 
									- ID + SequenceNumber and the UPDATE above - 
									- similar, but one x of the above as a string/text
									- ditto, but decimal
									- ditto, but both strings
									- ditto, both decimal

									and so on... 

							Finally, 
								IF composite keys don't work - with multiple rows. 
								then, the only 'fix'/work-around would be

									a. add a new IDENTITY or GUID column called, say, row_id. 
									b. doing ONE of the following: 
											i. changing the table's PK from, say, TaskID, StepID to -> row_id. 
													this ... positively sucks and wouldn't make sense in many environments
													plus... it just sucks and ... it sucks. 

											ii. LEAVING the existing, composite, PK 100% alone and as-is. 
												marking row_id as a 'surrogate' key. 
													this way, the table still 100% works as expected and auditing can/will happen based on this new 'key'. 

													the RUB/concern with this work-around is: 
														surrogate_keys, currently, are what we use if/when we can't find a DEFINITIVE key. 
															i could flip that around or something, but that's a bad idea. 
																Surrogate Keys <> CompositeKey-Link-Thingies. 
																	Meaning, I need a second table: dda.composite_key_workarounds

																	And, with such a key, behavior could be: 
																		A. WARN users about composite keys during install/configuration "hey, this is a composite key, multi-row updates will suck/fail, yous should 1. add a NEW_ID() and 2. a mapping in such and such table"
																		B. if/when the trigger detects that LEGIT PK rows are/were in the changed columns... 
																				if it's just 1x row... done and done (assuming it's easier to just grab before/after without looking up the 'work-around-composite-key'. 
																					otherwise, if it's > 1 row or using the work-around-composite_key is EASIER... just 'bind' on those values instead. 

															And, the take-away here is: 
																many environments might already have an IDENTITY or ROW_GUID_COL() type row in place anyhow - i.e., on their tables AND a composite key. 
																	erven if they don't, they MIGHT??? have some other column that IS a 'glue-y' enough (distinct enough per composite-key-pairs) that it COULD work. 
																		if not, adding this column, while it sucks, would be a small price to pay. 
																				adding this column though would, of course, be a size of data operation. 
																					BUT
																						I could help them implement that with docs and guidance on: 
																							1. ALTER yourTable ADD row_guid_magic uniqueidentifier NULL. 
																							2. NIBBLING UPDATEs. 
																							3. ALTER ... NON NULL + DEFAULT - to decrease down-time and so on. 


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
			@rawKeys = @rawKeys + [result] + N','
 		FROM 
			dda.[split_string](@pkColumns, N',', 1) 
		ORDER BY 
			row_id;

		SET @keys = LEFT(@keys, LEN(@keys) - 1);

		SELECT
			@columnNames = @columnNames + N'[d].' + QUOTENAME([column_name]) + N' [' + [column_name] + N'.from], ' + @crlf + @tab + @tab + @tab + N'[i2].' + QUOTENAME([column_name]) + N' [' + [column_name] + N'.to], ',
			@rawColumnNames = @rawColumnNames + [column_name] + N','
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
				UPDATE [#temp_inserted] SET [dda_trigger_id] = (SELECT TOP (1) [dda_trigger_id] FROM [#temp_deleted]);
				SET @joinKeys = N'[i2].[dda_trigger_id] = [d].[dda_trigger_id] '
			  END;
			ELSE BEGIN 
				-- vNEXT: 
				-- 1. Check for a secondary key/mapping in dda.secondary_keys. 
				-- 2. If that exists, SET @joinKeys = N'[i2].[key_name_1] = [d].[key_name_1] AND ... etc';
				--		done. 

				-- 3. If the above mappings do NOT exit: 
				--	@json/output will need to look like: [{ "keys": [{"Hmmm. not even sure this works"}], "detail":{[ "probably nothing here too?" }], "dump": {[ throw "deleted" and "inserted" into here as SELECT * from each" "}] }]
				--		so, yeah, actually... if/when there's NOT a secondary key and MULTIPLE ROWS were updated, I THINK the reality is... 
				--		i don't/won't have a 3rd node to add. I think there will ONLY be "deleted" and "inserted" results - the end? 

				RAISERROR(N'Multi-Row UPDATEs that change Primary Key Values are not YET supported. This change was allowed (vs ROLLED back/terminated), but NOT captured correctly.', 16, 1);
			END;
		END;

		SET @sql  = REPLACE(@sql, N'{FROM_CLAUSE}', N'[#temp_inserted] [i]');
		
		SET @sql = REPLACE(@sql, N'{key_columns}', @keys);
		SET @sql = REPLACE(@sql, N'{key_from_and_where}', N'[#temp_inserted] [i2] WHERE [i].[dda_trigger_id] = [i2].[dda_trigger_id]');

		SET @sql = REPLACE(@sql, N'{detail_columns}', @crlf + @tab + @tab + @tab + @columnNames + @crlf + @tab + @tab);
		SET @sql = REPLACE(@sql, N'{detail_from_and_where}', @crlf + @tab + @tab + @tab + N'[#temp_inserted] [i2]' + @crlf + @tab + @tab + @tab + N'INNER JOIN [#temp_deleted] [d] ON ' + @joinKeys + @crlf + @tab + @tab + N' WHERE [i].[dda_trigger_id] = [i2].[dda_trigger_id]');

	END;

	DECLARE @json nvarchar(MAX); 
	EXEC sp_executesql 
		@sql, 
		N'@json nvarchar(MAX) OUTPUT', 
		@json = @json OUTPUT;

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