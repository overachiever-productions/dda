/*

	REFERENCE:
		- License, documentation, and source code at: 
			https://github.com/overachiever-productions/dda/


*/



-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
/*


!!!! WARNING


-- 0. Make sure to run the following commands in the database you wish to target for audits (i.e., not master or any other db you might currently be in).
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */


USE [your database here];
GO


----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 1. Create dda schema:
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------


-- TODO: IF checks + exceptions if already exists
--IF SCHEMA_ID('dda') IS NOT NULL BEGIN
--	RAISERROR('WARNING: dda schema already exists - execution is being terminated and connection will be broken.', 21, 1) WITH LOG;
--END;
--GO 


IF SCHEMA_ID('dda') IS NULL BEGIN 
	EXEC('CREATE SCHEMA [dda] AUTHORIZATION [db_owner];');
END;
GO 

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 2. Core Tables:
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------

IF OBJECT_ID('dda.version_history', 'U') IS NULL BEGIN

	CREATE TABLE dda.version_history (
		version_id int IDENTITY(1,1) NOT NULL, 
		version_number varchar(20) NOT NULL, 
		[description] nvarchar(200) NULL, 
		deployed datetime NOT NULL CONSTRAINT DF_version_info_deployed DEFAULT GETDATE(), 
		CONSTRAINT PK_version_info PRIMARY KEY CLUSTERED (version_id)
	);

	EXEC sys.sp_addextendedproperty
		@name = 'dda',
		@value = 'TRUE',
		@level0type = 'Schema',
		@level0name = 'dda',
		@level1type = 'Table',
		@level1name = 'version_history';
END;

-----------------------------------
IF OBJECT_ID('dda.translation_tables') IS NULL BEGIN

	CREATE TABLE dda.translation_tables (
		[translation_table_id] int IDENTITY(1,1) NOT NULL, 
		[table_name] sysname NOT NULL, -- TODO: HAS to include schema - i.e., force a constraint or use a trigger... 
		[translated_name] sysname NOT NULL, 
		[notes] nvarchar(MAX) NULL,
		CONSTRAINT PK_translation_tables PRIMARY KEY NONCLUSTERED ([translation_table_id])
	); 

	CREATE UNIQUE CLUSTERED INDEX CLIX_translation_tables_by_table_name ON [dda].[translation_tables] ([table_name]);

END;


DROP TRIGGER IF EXISTS [dda].[rules_for_tables];
GO

CREATE TRIGGER [dda].[rules_for_tables] ON dda.[translation_tables] FOR INSERT, UPDATE
AS 
	-- NOTE: 
	--		Triggers are UGLY. Using them HERE makes sense given how infrequently they'll be executed. 
	--		In other words, do NOT take use of triggers here as an indication that using triggers to
	--			enforce business rules or logic in YOUR databases is any kind of best practice, as it
	--			almost certainly is NOT a best practice (for anything other than light-weight auditing).


	-- verify that table is in correct format: <schema>.<table>. 
	DECLARE @tableName sysname; 
	SELECT @tableName = [table_name] FROM [Inserted];

	DECLARE @dbNamePart sysname, @schemaNamePart sysname, @tableNamePart sysname;
	SELECT 
		@dbNamePart = PARSENAME(@tableName, 3),
		@schemaNamePart = PARSENAME(@tableName, 2), 
		@tableNamePart = PARSENAME(@tableName, 1);

	IF @dbNamePart IS NOT NULL BEGIN 
		RAISERROR(N'The [table_name] column MUST be specified in <schema_name>.<db_name> format. Database-name is not supported.', 16, 1);
		ROLLBACK;
		GOTO Finalize;
	END;

	IF @tableNamePart IS NULL BEGIN 
		RAISERROR('The [table_name] column MUST be specified in <schema_name>.<db_name> format.', 16, 1);
		ROLLBACK;
		GOTO Finalize;
	END;

	IF @schemaNamePart IS NULL BEGIN 
		-- check to see if dbo.<tableName> and suggest it if it does. either way, rollback/error. 
		IF EXISTS (SELECT NULL FROM sys.objects WHERE [schema_id] = 1 AND [name] = @tableNamePart) BEGIN 
			RAISERROR('Please specify a valid schema for table [%s] - i.e, ''[dbo].[%s]'' instead of just ''%s''.', 16, 1, @tableNamePart, @tableNamePart, @tableNamePart);
			ROLLBACK;
			GOTO Finalize;
		END;

		RAISERROR('The [table_name] column MUST be specified in <schema_name>.<db_name> format.', 16, 1);
		ROLLBACK;
		GOTO Finalize;
	END;

	IF NOT EXISTS (SELECT NULL FROM sys.objects WHERE [schema_id] = SCHEMA_ID(@schemaNamePart) AND [name] = @tableNamePart) BEGIN 
		PRINT N'WARNING: table [' + @schemaNamePart + N'].[' + @tableNamePart + N'] does NOT exist.';
		PRINT N' Mapping will still be added but won''t work until a matching table exists and is enabled for auditing.)';
	END;

Finalize:
GO


-----------------------------------
IF OBJECT_ID('dda.translation_columns') IS NULL BEGIN

	CREATE TABLE dda.translation_columns (
		[translation_column_id] int IDENTITY(1,1) NOT NULL, 
		[table_name] sysname NOT NULL, -- TODO: HAS to include schema - i.e., force a constraint or use a trigger... 
		[column_name] sysname NOT NULL, 
		[translated_name] sysname NOT NULL, 
		[notes] nvarchar(MAX) NULL,
		CONSTRAINT PK_translation_columns PRIMARY KEY NONCLUSTERED ([translation_column_id]) 
	); 

	CREATE UNIQUE CLUSTERED INDEX CLIX_translation_columns_by_table_and_column_name ON dda.[translation_columns] ([table_name], [column_name]);

END;

DROP TRIGGER IF EXISTS [dda].[rules_for_columns];
GO

CREATE TRIGGER [dda].[rules_for_columns] ON dda.[translation_columns] FOR INSERT, UPDATE
AS 
	-- NOTE: 
	--		Triggers are UGLY. Using them HERE makes sense given how infrequently they'll be executed. 
	--		In other words, do NOT take use of triggers here as an indication that using triggers to
	--			enforce business rules or logic in YOUR databases is any kind of best practice, as it
	--			almost certainly is NOT a best practice (for anything other than light-weight auditing).


	-- verify that table is in correct format: <schema>.<table>. 
	DECLARE @tableName sysname, @columnName sysname;
	SELECT 
		@tableName = [table_name] , 
		@columnName = [column_name]
	FROM [Inserted];

	DECLARE @dbNamePart sysname, @schemaNamePart sysname, @tableNamePart sysname;
	SELECT 
		@dbNamePart = PARSENAME(@tableName, 3),
		@schemaNamePart = PARSENAME(@tableName, 2), 
		@tableNamePart = PARSENAME(@tableName, 1);

	IF @dbNamePart IS NOT NULL BEGIN 
		RAISERROR(N'The [table_name] column MUST be specified in <schema_name>.<db_name> format. Database-name is not supported.', 16, 1);
		ROLLBACK;
		GOTO Finalize;
	END;

	IF @tableNamePart IS NULL BEGIN 
		RAISERROR('The [table_name] column MUST be specified in <schema_name>.<db_name> format.', 16, 1);
		ROLLBACK;
		GOTO Finalize;
	END;

	IF @schemaNamePart IS NULL BEGIN 
		-- check to see if dbo.<tableName> and suggest it if it does. either way, rollback/error. 
		IF EXISTS (SELECT NULL FROM sys.objects WHERE [schema_id] = 1 AND [name] = @tableNamePart) BEGIN 
			RAISERROR('Please specify a valid schema for table [%s] - i.e, ''[dbo].[%s]'' instead of just ''%s''.', 16, 1, @tableNamePart, @tableNamePart, @tableNamePart);
			ROLLBACK;
			GOTO Finalize;
		END;

		RAISERROR('The [table_name] column MUST be specified in <schema_name>.<db_name> format.', 16, 1);
		ROLLBACK;
		GOTO Finalize;
	END;

	IF NOT EXISTS (SELECT NULL FROM sys.objects WHERE [schema_id] = SCHEMA_ID(@schemaNamePart) AND [name] = @tableNamePart) BEGIN 
		PRINT N'WARNING: table [' + @schemaNamePart + N'].[' + @tableNamePart + N'] does NOT exist.';
		PRINT N' Mapping will still be added but won''t work until a matching table exists and is enabled for auditing.)';
	END;

	IF NOT EXISTS (SELECT NULL FROM sys.columns WHERE [object_id] = OBJECT_ID(@tableName) AND [name] = @columnName) BEGIN 
		PRINT N'WARNING: column [' + @columnName + N'] does NOT exist in the specified table.';
		PRINT N' Mapping will still be created, but will not work until a table-name+column-name match exists and is audited.';
	END;

Finalize:
GO



-----------------------------------
IF OBJECT_ID('dda.translation_values') IS NULL BEGIN

	CREATE TABLE dda.translation_values (
		[translation_key_id] int IDENTITY(1,1) NOT NULL, 
		[table_name] sysname NOT NULL, 
		[column_name] sysname NOT NULL, 
		[key_value] sysname NOT NULL, 
		[translation_value] sysname NOT NULL, 
		[notes] nvarchar(MAX) NULL,
		CONSTRAINT PK_translation_keys PRIMARY KEY NONCLUSTERED ([translation_key_id])
	);

	CREATE UNIQUE CLUSTERED INDEX CLIX_translation_values_by_identifiers ON dda.[translation_values] ([table_name], [column_name], [key_value]);

END;

DROP TRIGGER IF EXISTS [dda].[rules_for_values];
GO

CREATE TRIGGER [dda].[rules_for_values] ON dda.[translation_values] FOR INSERT, UPDATE
AS 
	-- NOTE: 
	--		Triggers are UGLY. Using them HERE makes sense given how infrequently they'll be executed. 
	--		In other words, do NOT take use of triggers here as an indication that using triggers to
	--			enforce business rules or logic in YOUR databases is any kind of best practice, as it
	--			almost certainly is NOT a best practice (for anything other than light-weight auditing).


	-- verify that table is in correct format: <schema>.<table>. 
	DECLARE @tableName sysname, @columnName sysname;
	SELECT 
		@tableName = [table_name] , 
		@columnName = [column_name]
	FROM [Inserted];

	DECLARE @dbNamePart sysname, @schemaNamePart sysname, @tableNamePart sysname;
	SELECT 
		@dbNamePart = PARSENAME(@tableName, 3),
		@schemaNamePart = PARSENAME(@tableName, 2), 
		@tableNamePart = PARSENAME(@tableName, 1);

	IF @dbNamePart IS NOT NULL BEGIN 
		RAISERROR(N'The [table_name] column MUST be specified in <schema_name>.<db_name> format. Database-name is not supported.', 16, 1);
		ROLLBACK;
		GOTO Finalize;
	END;

	IF @tableNamePart IS NULL BEGIN 
		RAISERROR('The [table_name] column MUST be specified in <schema_name>.<db_name> format.', 16, 1);
		ROLLBACK;
		GOTO Finalize;
	END;

	IF @schemaNamePart IS NULL BEGIN 
		-- check to see if dbo.<tableName> and suggest it if it does. either way, rollback/error. 
		IF EXISTS (SELECT NULL FROM sys.objects WHERE [schema_id] = 1 AND [name] = @tableNamePart) BEGIN 
			RAISERROR('Please specify a valid schema for table [%s] - i.e, ''[dbo].[%s]'' instead of just ''%s''.', 16, 1, @tableNamePart, @tableNamePart, @tableNamePart);
			ROLLBACK;
			GOTO Finalize;
		END;

		RAISERROR('The [table_name] column MUST be specified in <schema_name>.<db_name> format.', 16, 1);
		ROLLBACK;
		GOTO Finalize;
	END;

	IF NOT EXISTS (SELECT NULL FROM sys.objects WHERE [schema_id] = SCHEMA_ID(@schemaNamePart) AND [name] = @tableNamePart) BEGIN 
		PRINT N'WARNING: table [' + @schemaNamePart + N'].[' + @tableNamePart + N'] does NOT exist.';
		PRINT N' Mapping will still be added but won''t work until a matching table exists and is enabled for auditing.)';
	END;

	IF NOT EXISTS (SELECT NULL FROM sys.columns WHERE [object_id] = OBJECT_ID(@tableName) AND [name] = @columnName) BEGIN 
		PRINT N'WARNING: column [' + @columnName + N'] does NOT exist in the specified table.';
		PRINT N' Mapping will still be created, but will not work until a table-name+column-name match exists and is audited.';
	END;

Finalize:
GO


-----------------------------------
IF OBJECT_ID('dda.trigger_host') IS NULL BEGIN

	CREATE TABLE dda.trigger_host (
		[notice] sysname NOT NULL 
	); 

	INSERT INTO dda.trigger_host ([notice]) VALUES (N'Table REQUIRED: provides TEMPLATE for triggers.');

END;


-----------------------------------
IF OBJECT_ID('dda.surrogate_keys', 'U') IS NULL BEGIN

	CREATE TABLE dda.surrogate_keys (
		[surrogate_id] int IDENTITY(1,1) NOT NULL, 
		[schema] sysname NOT NULL, 
		[table] sysname NOT NULL, 
		[serialized_surrogate_columns] nvarchar(260) NOT NULL, 
		[definition_date] datetime CONSTRAINT DF_surrogate_keys_definition_date DEFAULT (GETDATE()), 
		[notes] nvarchar(MAX) NULL, 
		CONSTRAINT PK_surrogate_keys PRIMARY KEY CLUSTERED ([schema], [table])
	);

END;


-----------------------------------
IF OBJECT_ID('dda.audits', 'U') IS NULL BEGIN

	CREATE TABLE dda.audits (
		[audit_id] int IDENTITY(1,1) NOT NULL,  
		[timestamp] datetime NOT NULL CONSTRAINT DF_data_audit_timestamp DEFAULT (GETDATE()), 
		[schema] sysname NOT NULL, 
		[table] sysname NOT NULL, 
		[user] sysname NOT NULL, 
		[operation] char(9) NOT NULL, 
		[transaction_id] int NULL,
		[row_count] int NOT NULL, 
		[audit] nvarchar(MAX) CONSTRAINT CK_audit_data_data_is_json CHECK (ISJSON([audit]) > 0), 
		CONSTRAINT PK_audits PRIMARY KEY NONCLUSTERED ([audit_id])
	); 

	CREATE CLUSTERED INDEX CLIX_audits_by_timestamp ON dda.[audits] ([timestamp]);

	CREATE NONCLUSTERED INDEX IX_audits_by_user ON dda.[audits] ([user], [timestamp], [schema], [table]);

	CREATE NONCLUSTERED INDEX IX_audits_by_table ON dda.[audits] ([schema], [table], [timestamp]);

END;



----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 3. <Placeholder for Cleanup / Refactor from Previous Versions>:
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------



----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 4. Deploy new/updated code.
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------------------------------------
-- Meta-Data and Capture-Related Functions
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
/*


*/

DROP FUNCTION IF EXISTS dda.[split_string];
GO

CREATE FUNCTION [dda].[split_string](@serialized nvarchar(MAX), @delimiter nvarchar(20), @TrimResults bit)
RETURNS @Results TABLE (row_id int IDENTITY NOT NULL, result nvarchar(MAX))
AS 
	-- [v0.9.3510.8] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	BEGIN

	-- Code lifted from S4 (and, as such, is a DRY violation): https://github.com/overachiever-productions/s4/ 
	
	IF NULLIF(@serialized,'') IS NOT NULL AND DATALENGTH(@delimiter) >= 1 BEGIN
		IF @delimiter = N' ' BEGIN 
			-- this approach is going to be MUCH slower, but works for space delimiter... 
			DECLARE @p int; 
			DECLARE @s nvarchar(MAX);
			WHILE CHARINDEX(N' ', @serialized) > 0 BEGIN 
				SET @p = CHARINDEX(N' ', @serialized);
				SET @s = SUBSTRING(@serialized, 1, @p - 1); 
			
				INSERT INTO @Results ([result])
				VALUES(@s);

				SELECT @serialized = SUBSTRING(@serialized, @p + 1, LEN(@serialized) - @p);
			END;
			
			INSERT INTO @Results ([result])
			VALUES (@serialized);

		  END; 
		ELSE BEGIN

			DECLARE @MaxLength int = LEN(@serialized) + LEN(@delimiter);

			WITH tally (n) AS ( 
				SELECT TOP (@MaxLength) 
					ROW_NUMBER() OVER (ORDER BY o1.[name]) AS n
				FROM sys.all_objects o1 
				CROSS JOIN sys.all_objects o2
			)

			INSERT INTO @Results ([result])
			SELECT 
				SUBSTRING(@serialized, n, CHARINDEX(@delimiter, @serialized + @delimiter, n) - n) [result]
			FROM 
				tally 
			WHERE 
				n <= LEN(@serialized) AND
				LEN(@delimiter) <= LEN(@serialized) AND
				RTRIM(LTRIM(SUBSTRING(@delimiter + @serialized, n, LEN(@delimiter)))) = @delimiter
			ORDER BY 
				 n;
		END;

		IF @TrimResults = 1 BEGIN
			UPDATE @Results SET [result] = LTRIM(RTRIM([result])) WHERE DATALENGTH([result]) > 0;
		END;

	END;

	RETURN;
END;
GO


-----------------------------------
/*


*/

DROP FUNCTION IF EXISTS dda.translate_modified_columns;
GO

CREATE FUNCTION dda.[translate_modified_columns](@TargetTable sysname, @ChangeMap varbinary(1024)) 
RETURNS @changes table (column_id int NOT NULL, modified bit NOT NULL, column_name sysname NULL)
AS 
	-- [v0.9.3510.8] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	BEGIN 
		SET @TargetTable = NULLIF(@TargetTable, N'');
		IF @TargetTable IS NOT NULL BEGIN 
			DECLARE @object_id int = (SELECT OBJECT_ID(@TargetTable));

			-- Elegant bitwise manipulation from Jeffrey Yao via: https://www.mssqltips.com/sqlservertip/6497/how-to-identify-which-sql-server-columns-changed-in-a-update/ 

			IF EXISTS (SELECT NULL FROM sys.tables WHERE object_id = @object_id) BEGIN 
				DECLARE @currentMapSlot int = 1; 
				DECLARE @columnMask binary; 

				WHILE (@currentMapSlot < LEN(@ChangeMap) + 1) BEGIN 
					SET @columnMask = SUBSTRING(@ChangeMap, @currentMapSlot, 1);

					INSERT INTO @changes (column_id, modified)
					SELECT (@currentMapSlot - 1) * 8 + 1, @columnMask & 1 UNION ALL		
					SELECT (@currentMapSlot - 1) * 8 + 2, @columnMask & 2 UNION ALL 							   
					SELECT (@currentMapSlot - 1) * 8 + 3, @columnMask & 4 UNION ALL 							  
					SELECT (@currentMapSlot - 1) * 8 + 4, @columnMask & 8 UNION ALL 							   
					SELECT (@currentMapSlot - 1) * 8 + 5, @columnMask & 16 UNION ALL
					SELECT (@currentMapSlot - 1) * 8 + 6, @columnMask & 32 UNION ALL 
					SELECT (@currentMapSlot - 1) * 8 + 7, @columnMask & 64 UNION ALL 
					SELECT (@currentMapSlot - 1) * 8 + 8, @columnMask & 128
		
					SET @currentMapSlot = @currentMapSlot + 1;
				END;

				WITH column_names AS ( 
					SELECT [column_id], [name]
					FROM sys.columns 
					WHERE [object_id] = @object_id
				)
				UPDATE x 
				SET 
					x.column_name = c.[name]
				FROM 
					@changes x 
					INNER JOIN [column_names] c ON [x].[column_id] = [c].[column_id]
				WHERE 
					x.[column_name] IS NULL;

				DELETE FROM @changes WHERE [column_name] IS NULL;

			END;
		END;
		
		RETURN;
	END;
GO



------------------------------------------------------------------------------------------------------------------------------------------------------
-- DDA Trigger 
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
/*

	TODO: 
		current automation around deployment + updates of dynamic triggers is hard-coded/kludgey around exact
		format/specification of the "FOR INSERT, UPDATE, DELETE" text in the following trigger definition. 
			i.e., changing whitespace can/could/would-probably break 'stuff'. 

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

	-- [v0.9.3510.8] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

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
	DECLARE @txID int = CAST(LEFT(CAST(CURRENT_TRANSACTION_ID() AS sysname), 9) AS int);

	-- Determine Operation Type: INSERT, UPDATE, or DELETE: 
	DECLARE @operationType sysname; 
	SELECT 
		@operationType = CASE 
			WHEN EXISTS(SELECT NULL FROM INSERTED) AND EXISTS(SELECT NULL FROM DELETED) THEN N'UPDATE'
			WHEN EXISTS(SELECT NULL FROM INSERTED) THEN N'INSERT'
			ELSE N'DELETE'
		END;

	IF UPPER(@operationType) IN (N'INSERT', N'UPDATE') BEGIN
		SELECT * INTO #temp_inserted FROM inserted;
		SELECT @rowCount = @@ROWCOUNT;
	END;
	
	IF UPPER(@operationType) IN (N'DELETE', N'UPDATE') BEGIN
		SELECT * INTO #temp_deleted FROM deleted;
		SELECT @rowCount = ISNULL(NULLIF(@rowCount, -1), @@ROWCOUNT);
	END;

	IF @rowCount < 1 BEGIN 
		GOTO Cleanup; -- nothing to document/audit - bail:
	END;

	DECLARE @template nvarchar(MAX) = N'SELECT @json = (SELECT 
		{AUDIT_COLUMNS} 
	FROM 
		{AUDIT_FROM} FOR JSON PATH	
);';

	DECLARE @sql nvarchar(MAX) = @template;

	DECLARE @pkColumns nvarchar(MAX) = NULL;
	EXEC dda.[extract_key_columns] 
		@TargetSchema = @schemaName,
		@TargetTable = @tableName, 
		@Output = @pkColumns OUTPUT;

	IF NULLIF(@pkColumns, N'') IS NULL BEGIN 
		-- Sadly, there is SOMEHOW not a PK defined or any surrogate mappings defined ANYMORE. (Trigger-creation scaffolding would have verified ONE or the OTHER.) 
		RAISERROR('Data Auditing Exception - No Primary Key or suitable surrogate defined against table [%s].[%s].', 16, 1, @schemaName, @tableName);
		GOTO Cleanup;
	END;

	DECLARE @key nvarchar(MAX) = N'';
	DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10); 
	DECLARE @tab nchar(1) = NCHAR(9);

	-- INSERT/DELETE: grab everything.
	IF UPPER(@operationType) IN (N'INSERT', N'DELETE') BEGIN 
		SET @sql = REPLACE(@sql, N'{AUDIT_COLUMNS}', CASE WHEN @operationType = N'INSERT' THEN N'i.*' ELSE N'd.*' END);
		SET @sql = REPLACE(@sql, N'{AUDIT_FROM}', CASE WHEN @operationType = N'INSERT' THEN N'#temp_inserted i' ELSE N'#temp_deleted d' END);
	END;
	
	-- UPDATE: use changeMap to grab modified columns only:
	IF UPPER(@operationType) = N'UPDATE' BEGIN 

		DECLARE @join nvarchar(MAX) = N'';

-- TODO: Look into detecting non-UPDATING updates i.e., SET x = y, a = b ... as the UPDATE but where x is ALREADY y, and a is ALREADY b 
--			(i.e., full or partial removal of 'duplicates'/non-changes is what we're after - i.e., if x and a were only columns in SET of UPDATE and there are no changes, 
--				maybe BAIL and don't record this? whereas if it was x OR a that had a change, just record the ONE that changed?
		DECLARE @changeMap varbinary(1024) = (SELECT COLUMNS_UPDATED());

		DECLARE @columnNames nvarchar(MAX) = N'';
		SELECT
			@columnNames = @columnNames + N'[d].' + QUOTENAME([column_name]) + N' [' + [column_name] + N'.from], ' + @crlf + @tab + @tab + N'[i].' + QUOTENAME([column_name]) + N' [' + [column_name] + N'.to], '
		FROM 
			dda.[translate_modified_columns](@auditedTable, @changeMap)
		WHERE 
			[modified] = 1 
		ORDER BY 
			[column_id]; 

		IF LEN(@columnNames) > 0 SET @columnNames = LEFT(@columnNames, LEN(@columnNames) - 1);

		DECLARE @from nvarchar(MAX) = N'#temp_deleted d ' + @crlf + @tab + @tab + N'INNER JOIN #temp_inserted i ON ';

		SELECT
			@join = @join + N'[d].' + QUOTENAME([result]) + N' = [i].' + QUOTENAME([result]) + N' AND ' 
		FROM 
			dda.[split_string](@pkColumns, N',', 1) 
		ORDER BY 
			row_id;

		SET @join = LEFT(@join, LEN(@join) - 4);
		SET @from = @from + @join;

		SET @sql = REPLACE(@sql, N'{AUDIT_COLUMNS}', @columnNames);
		SET @sql = REPLACE(@sql, N'{AUDIT_FROM}', @from);
	END;

	DECLARE @json nvarchar(MAX); 
	EXEC sp_executesql 
		@sql, 
		N'@json nvarchar(MAX) OUTPUT', 
		@json = @json OUTPUT;


	-- Define + Populate Key Info:
	SELECT
		@key = @key + CASE WHEN @operationType = N'INSERT' THEN N'[i].' ELSE N'[d].' END + QUOTENAME([result]) + N' [' + [result] + N'], '
	FROM 
		dda.[split_string](@pkColumns, N',', 1) 
	ORDER BY 
		row_id;

	SET @key = LEFT(@key, LEN(@key) -1);

	DECLARE @keyOutput nvarchar(MAX);
	SET @sql = N'SELECT @keyOutput = (SELECT ' + @key + N' FROM ' + CASE WHEN @operationType = N'INSERT' THEN N'#temp_inserted i' ELSE N'#temp_deleted d' END + N' FOR JSON PATH);';

	EXEC sp_executesql
		@sql, 
		N'@keyOutput nvarchar(MAX) OUTPUT', 
		@keyOutput = @keyOutput OUTPUT;
		
	-- Bind Key + Detail Elements (manually) into a new JSON object:
	SET @json = N'[{"key":' + @keyOutput + N', "detail":' + @json + N'}]';

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


------------------------------------------------------------------------------------------------------------------------------------------------------
-- Search/View
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
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

	-- [v0.9.3510.8] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

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
		[type] int NOT  NULL,
		[translated_column] sysname NULL, 
		[value] nvarchar(MAX) NULL, -- TODO: should I allow nulls here? 
		[translated_value] sysname NULL, 
		[from_value] nvarchar(MAX) NULL, 
		[from_value_type] int NULL, 
		[translated_from_value] sysname NULL, 
		[to_value] sysname NULL, 
		[to_value_type] int NULL,
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
		[type],
		[value]
	)
	SELECT 
		N'key',
		x.[table], 
		x.[row_number],
		y.[Key] [column], 
		y.[Type] [type],
		y.[Value] [value] 
	FROM 
		[#raw_data] x
		OUTER APPLY OPENJSON(JSON_QUERY(x.[change_details], '$[0].key'), '$') z
		CROSS APPLY OPENJSON(z.[Value], N'$') y
	WHERE 
		y.[Key] IS NOT NULL 
		AND y.[Value] IS NOT NULL;

	INSERT INTO [#key_value_pairs] (
		[kvp_type],
		[table],
		[row_number],
		[column],
		[type],
		[value]
	)
	SELECT 
		N'detail',
		x.[table], 
		x.[row_number],
		y.[Key] [column], 
		y.[Type] [type],
		y.[Value] [value]
	FROM 
		[#raw_data] x 
		OUTER APPLY OPENJSON(JSON_QUERY(x.[change_details], '$[0].detail'), '$') z
		CROSS APPLY OPENJSON(z.[Value], N'$') y
	WHERE 
		y.[Key] IS NOT NULl
		AND y.[Value] IS NOT NULL;

-- TODO: account for type changes to/from NULL - i.e., type = 0: https://docs.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql?view=sql-server-ver15#return-value
	UPDATE [#key_value_pairs] 
	SET 
		[from_value] = JSON_VALUE([value], N'$.from'), 
		[from_value_type] = CASE WHEN [value] LIKE N'%"from":"%' THEN 1 ELSE 0 END,
		[to_value] = JSON_VALUE([value], N'$.to'),
		[to_value_type] = CASE WHEN [value] LIKE N'%,"to":"%' THEN 1 ELSE 0 END 
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

	-- State from/to value translations:
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
		[translated_update_value] = N'{"from":' + CASE 
				WHEN [from_value_type] = 1 THEN N'"' + ISNULL([translated_from_value], [from_value]) + N'"' 
				ELSE ISNULL([translated_from_value], [from_value])
			END + N', "to":' + CASE 
				WHEN [to_value_type] = 1 THEN N'"' + ISNULL([translated_to_value], [to_value]) + N'"'
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
				(SELECT [column] [key_col], [value] [key_val] FROM [#translated_kvps] x2 WHERE x2.[table] = @currentTranslationTable AND x.[row_number] = x2.[row_number] AND x2.[kvp_type] = N'key' /* ORDER BY xxx here*/ FOR JSON AUTO) [key_data]
			FROM 
				[row_numbers] x 
		), 
		[details] AS (

			SELECT 
				x.[row_number],
				(SELECT [column] [detail_col], [value] [detail_val] FROM [#translated_kvps] x2 WHERE x2.[table] = @currentTranslationTable AND x.[row_number] = x2.[row_number] AND x2.[kvp_type] = N'detail' /* ORDER BY xxx here*/ FOR JSON AUTO) [detail_data]
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

-- TODO: I somehow lost the .type in here... i..e, I'm getting it from ... OPENJSON... which isn't viable - cuz everything has been reverted to a string... 
		-- Keys Translation: 
		WITH [streamlined] AS ( 
			SELECT 
				[row_number], 
				[operation_type], 
				[row_count], 
				[key_data] [data]
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
				[detail_data] [data]
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
			WHEN [translated_change_key] IS NOT NULL THEN N'[{"key":[{' + [translated_change_key] + N'}],"detail":[{' + [translated_change_detail] + N'}]}]'
			ELSE [change_details]
		END [change_details] 
	FROM [#raw_data];

	RETURN 0;
GO


-----------------------------------
/*
	
	Use-Case:
		- Audits / Triggers are deployed and capturing data. 
		- There isn't yet a GUI for reviewing audit data (or an admin/dev/whatever is poking around in the database). 
		- User is capable of running sproc commands (e.g., EXEC dda.get_audit_data to find a couple of rows they'd like to see)
		- But, they're not wild about trying to view change details crammed into JSON. 

		This sproc lets a user query a single audit row, and (dynamically) 'explodes' the JSON data for easier review. 

		Further, the option to transform (or NOT) the data is present as well (useful for troubleshooting/debugging app changes and so on). 

*/

DROP PROC IF EXISTS dda.get_audit_row; 
GO 

CREATE PROC dda.get_audit_row 
	@AuditId					int, 
	@TransformOutput			bit		= 1
AS 
	SET NOCOUNT ON; 

	-- [v0.9.3510.8] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 





	SELECT * FROM [dda].[audits]


------------------------------------------------------------------------------------------------------------------------------------------------------
-- Utilities:
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------

DROP PROC IF EXISTS dda.enable_table_auditing; 
GO 

CREATE PROC dda.enable_table_auditing 
	@TargetSchema				sysname				= N'dbo', 
	@TargetTable				sysname, 
	@TriggerNamePattern			sysname				= N'ddat_{0}', 
	@SurrogateKeys				nvarchar(260)		= NULL, 
	@PrintOnly					bit					= 0
AS 
	SET NOCOUNT ON; 

	-- [v0.9.3510.8] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	SET @TargetTable = NULLIF(@TargetTable, N'');
	SET @SurrogateKeys = NULLIF(@SurrogateKeys, N'');
	SET @TargetSchema = ISNULL(NULLIF(@TargetSchema, N''), N'dbo');
	SET @TriggerNamePattern = ISNULL(NULLIF(@TriggerNamePattern, N''), N'ddat_{0}');

	-- verify table exists, doesn't already have a dynamic data auditing (DDA) trigger, and has a PK or that we have surrogate info: 
	DECLARE @objectName sysname = QUOTENAME(@TargetSchema) + N'.' + QUOTENAME(@TargetTable);

	IF @objectName IS NULL BEGIN 
		RAISERROR('Invalid (NULL) table or schema name provided. (Provided values were: table -> %s, schema -> %s.)', 16, 1, @TargetTable, @TargetSchema);
		RETURN -1;
	END;

	IF OBJECT_ID(@objectName) IS NULL BEGIN 
		RAISERROR('Invalid Table-Name specified for addition of auditing triggers: %s. Please check your input and try again.', 16, 1);
		RETURN -10;
	END;

	DECLARE @objectID int; 
	SELECT @objectID = object_id FROM sys.objects WHERE [schema_id] = SCHEMA_ID(@TargetSchema) AND [name] = @TargetTable AND [type] = N'U';

	IF EXISTS (
		SELECT NULL 
		FROM sys.[triggers] t INNER JOIN sys.[extended_properties] p ON t.[object_id] = p.[major_id] 
		WHERE t.[parent_id] = @objectID AND p.[name] = N'DDATrigger' AND p.[value] = 'true'
	) BEGIN
		RAISERROR(N'Target Table (%s) already has a dynamic data auditing (DDA) trigger defined. Please review existing triggers on table.', 16, 1, @objectName);
		RETURN -20;
	END;

	DECLARE @keyColumns nvarchar(MAX) = NULL;
	EXEC dda.[extract_key_columns] 
		@TargetSchema = @TargetSchema, 
		@TargetTable = @TargetTable, 
		@Output = @keyColumns OUTPUT;
	
	IF NULLIF(@keyColumns, N'') IS NULL BEGIN 
		IF @SurrogateKeys IS NOT NULL BEGIN 

			INSERT INTO dda.[surrogate_keys] (
				[schema],
				[table],
				[serialized_surrogate_columns]
			)
			VALUES	(
				@TargetSchema,
				@TargetTable,
				@SurrogateKeys
			);

			PRINT N'NOTE: Added Definition of the following serialized surrogate columns to dda.surrogate_keys for table ' + @objectName + N'; Keys -> ' + @SurrogateKeys + N'.';

			SET @keyColumns = NULL;
			EXEC dda.[extract_key_columns] 
				@TargetSchema = @TargetSchema, 
				@TargetTable = @TargetTable, 
				@Output = @keyColumns OUTPUT;

			IF NULLIF(@keyColumns, N'') IS NOT NULL BEGIN
				GOTO EndChecks;
			END;
		END; 

		RAISERROR(N'Target Table %s does NOT have an Explicit Primary Key defined - nor were @SurrogateKeys provided for configuration/setup.', 16, 1);
		RETURN -25;
	END;

EndChecks:
	-- don't allow audits against dda.audits:
	IF LOWER(@objectName) = N'[dda].[audits]' BEGIN 
		RAISERROR(N'Table dda.audits can NOT be the target of auditing (to prevent ''feedback loops'').', 16, 1);
		RETURN -30;
	END;

	-- create the trigger and mark it as a DDA trigger. 
	DECLARE @definitionID int; 
	DECLARE @definition nvarchar(MAX); 
	
	SELECT @definitionID = [object_id] FROM sys.[triggers] WHERE [name] = N'dynamic_data_auditing_trigger_template' AND [parent_id] = OBJECT_ID('dda.trigger_host');

	IF @definitionID IS NULL BEGIN 
		-- guessing the chances of this are UNLIKELY (i.e., can't see, say, this SPROC existing but the trigger being gone?), but...still, need to account for this. 
		RAISERROR(N'Dynamic Data Auditing Trigger Template NOT found against table dda.trigger_host. Please re-deploy DDA plumbing before continuing.', 16, -1);
		RETURN -32; 
	END;

	SELECT @definition = [definition] FROM sys.[sql_modules] WHERE [object_id] = @definitionID;
	DECLARE @pattern nvarchar(MAX) = N'%FOR INSERT, UPDATE, DELETE%';
	DECLARE @bodyStart int = PATINDEX(@pattern, @definition);

	DECLARE @body nvarchar(MAX) = SUBSTRING(@definition, @bodyStart, LEN(@definition) - @bodyStart);

	DECLARE @triggerName sysname; 
	IF @TriggerNamePattern NOT LIKE N'%{0}%' 
		SET @triggerName = @TriggerNamePattern; 
	ELSE 
		SET @triggerName = REPLACE(@TriggerNamePattern, N'{0}', @TargetTable);

	DECLARE @sql nvarchar(MAX) = N'CREATE TRIGGER ' + QUOTENAME(@TargetSchema) + N'.' + QUOTENAME(@triggerName) + N' ON ' + @objectName + N' ' + @body;
	
--EXEC [admindb].dbo.[print_long_string] @sql;

	IF @PrintOnly = 1 BEGIN 
		PRINT @sql;
	  END;
	ELSE BEGIN 
		EXEC sp_executesql @sql;

		-- mark the trigger as a DDAT:
		EXEC [sys].[sp_addextendedproperty]
			@name = N'DDATrigger',
			@value = N'true',
			@level0type = 'SCHEMA',
			@level0name = @TargetSchema,
			@level1type = 'TABLE',
			@level1name = @TargetTable,
			@level2type = 'TRIGGER',
			@level2name = @triggerName;
	END;

	RETURN 0;
GO


-----------------------------------
DROP PROC IF EXISTS dda.update_trigger_definitions; 
GO 

CREATE PROC dda.update_trigger_definitions 
	@PrintOnly				bit				= 1			-- default to NON-modifying execution (i.e., require explicit change to modify).
AS 
	SET NOCOUNT ON; 

	-- [v0.9.3510.8] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	-- load definition for the NEW trigger:
	DECLARE @definitionID int; 
	DECLARE @definition nvarchar(MAX); 
	
	SELECT @definitionID = [object_id] FROM sys.[triggers] WHERE [name] = N'dynamic_data_auditing_trigger_template' AND [parent_id] = OBJECT_ID('dda.trigger_host');

	IF @definitionID IS NULL BEGIN 
		-- guessing the chances of this are UNLIKELY (i.e., can't see, say, this SPROC existing but the trigger being gone?), but...still, need to account for this. 
		RAISERROR(N'Dynamic Data Auditing Trigger Template NOT found against table dda.trigger_host. Please re-deploy DDA plumbing before continuing.', 16, -1);
		RETURN -32; 
	END;

	SELECT @definition = [definition] FROM sys.[sql_modules] WHERE [object_id] = @definitionID;
	DECLARE @pattern nvarchar(MAX) = N'%FOR INSERT, UPDATE, DELETE%';
	DECLARE @bodyStart int = PATINDEX(@pattern, @definition);

	DECLARE @body nvarchar(MAX) = SUBSTRING(@definition, @bodyStart, LEN(@definition) - @bodyStart);


	IF @PrintOnly = 1 BEGIN 
		PRINT N'/* ------------------------------------------------------------------------------------------------------------------';
		PRINT N'';
		PRINT N'NOTE: ';
		PRINT N'	The @PrintOnly Parameter for this stored procedure defaults to a value of 1 - which means';
		PRINT N'		that this sproc will not, by DEFAULT, modify existing triggers. ';
		PRINT N'		Instead, by default, this sproc will SHOW you what it WOULD do (i.e., ''print only'' IF it '; 
		PRINT N'		were executed with @PrintOnly = 0.';
		PRINT N'';
		PRINT N'	To execute changes (after you''ve reviewed them), re-execute with @PrintOnly = 0.';
		PRINT N'		EXAMPLE: ';
		PRINT N'			EXEC dda.update_trigger_definitions @PrintOnly = 0;'
		PRINT N'';
		PRINT N'---------------------------------------------------------------------------------------------------------------------';
		PRINT N'*/'
		PRINT N'';
		PRINT N'';

		PRINT N'/* ------------------------------------------------------------------------------------------------------------------';
		PRINT N'';
		PRINT N'-- NEW BODY/DEFINITION of dynamic trigger will be as follows: ';
		PRINT N'';
		PRINT N'';
		PRINT N'ALTER [<trigger_name>] ON [<trigger_table>] ' + @body;
		PRINT N'';
		PRINT N'';
		PRINT N'---------------------------------------------------------------------------------------------------------------------';
		PRINT N'*/'

	END;

	CREATE TABLE #dynamic_triggers (
		[parent_table] nvarchar(260) NULL,
		[trigger_name] nvarchar(260) NULL,
		[for_insert] int NULL,
		[for_update] int NULL,
		[for_delete] int NULL,
		[is_disabled] bit NOT NULL,
		[create_date] datetime NOT NULL,
		[modify_date] datetime NOT NULL,
		[trigger_object_id] int NOT NULL,
		[parent_table_id] int NOT NULL
	);
	
	INSERT INTO [#dynamic_triggers] (
		[parent_table],
		[trigger_name],
		[for_insert],
		[for_update],
		[for_delete],
		[is_disabled],
		[create_date],
		[modify_date],
		[trigger_object_id],
		[parent_table_id]
	)
	EXEC dda.[list_dynamic_triggers];

	IF NOT EXISTS(SELECT NULL FROM [#dynamic_triggers]) BEGIN 
		RAISERROR(N'No tables with dynamic triggers found. Please execute dda.list_dynamic_triggers and/or deploy dynamic triggers before attempting to run updates.', 16, 1);
		RETURN 51;
	END;

	DECLARE @triggerName sysname, @tableName sysname;
	DECLARE @disabled bit, @insert bit, @update bit, @delete bit;
	
	DECLARE @firstAs int = PATINDEX(N'%AS%', @body);
	SET @body = SUBSTRING(@body, @firstAs, LEN(@body) - @firstAs);

	DECLARE @scope sysname;
	DECLARE @scopeCount int;
	DECLARE @directive nvarchar(MAX);
	DECLARE @directiveTemplate nvarchar(MAX) = N'ALTER TRIGGER {triggerName} ON {tableName} FOR {scope}
';
	DECLARE @sql nvarchar(MAX);

	DECLARE @errorMessage nvarchar(MAX);
	DECLARE @failures table (
		[failure_id] int IDENTITY(1,1) NOT NULL, 
		[trigger_name] sysname NOT NULL,
		[table_name] sysname NOT NULL, 
		[executed_command] nvarchar(MAX) NOT NULL,
		[error] nvarchar(MAX) NULL 
	);

	DECLARE [cursorName] CURSOR LOCAL FAST_FORWARD FOR 
	SELECT 
		[trigger_name],
		[parent_table],
		[is_disabled],
		[for_insert],
		[for_update],
		[for_delete]
	FROM 
		[#dynamic_triggers];
	
	OPEN [cursorName];
	FETCH NEXT FROM [cursorName] INTO @triggerName, @tableName, @disabled, @insert, @update, @delete;
	
	WHILE @@FETCH_STATUS = 0 BEGIN
	
		SET @scope = N'';
		SET @scopeCount = 0;

		IF @insert = 1 BEGIN 
			SET @scope = N'INSERT';
			SET @scopeCount = @scopeCount + 1;
		END;

		IF @update = 1 BEGIN 
			SET @scope = @scope + CASE WHEN @scopeCount > 0 THEN N', ' ELSE N'' END + N'UPDATE';
			SET @scopeCount = @scopeCount + 1;
		END;
		
		IF @delete = 1 BEGIN 
			SET @scope = @scope + CASE WHEN @scopeCount > 0 THEN N', ' ELSE N'' END + N'DELETE';
			SET @scopeCount = @scopeCount + 1;
		END;

		SET @directive = REPLACE(@directiveTemplate, N'{triggerName}', @triggerName);
		SET @directive = REPLACE(@directive, N'{tableName}', @tableName);
		SET @directive = REPLACE(@directive, N'{scope}', @scope);

		IF @scopeCount <> 3 BEGIN 
			PRINT N'WARNING: Non-standard Trigger Scope detected - current sproc is NOT scoped for INSERT, UPDATE, DELETE.';
		END;

		IF @disabled = 1 BEGIN 
			PRINT N'WARNING: Disabled Trigger Detected.';
		END;

		IF @PrintOnly = 1 BEGIN
			PRINT N'-- IF @PrintOnly were set to 0, the following ALTER would be executed:'
			PRINT @sql + N'AS '
			PRINT N'     .... <trigger_body_here>...';
			PRINT N''
			PRINT N'GO';
		  END; 
		ELSE BEGIN 
			SET @sql = @directive + @body;

			BEGIN TRY
				BEGIN TRAN;

					EXEC sp_executesql 
						@sql;

				COMMIT;

				PRINT N'Updated ' + @triggerName + N' on ' + @tableName + N'....';
			END TRY
			BEGIN CATCH 
				
				ROLLBACK;
				
				SELECT @errorMessage = CONCAT(N'Error Number: ', ERROR_NUMBER(), N'. Line: ', ERROR_LINE(), N'. Error Message: ' + ERROR_MESSAGE());
				INSERT INTO @failures (
					[trigger_name],
					[table_name],
					[executed_command],
					[error]
				)
				VALUES	(
					@triggerName, 
					@tableName, 
					@sql,
					@errorMessage
				);

			END CATCH;

		END;
	
		FETCH NEXT FROM [cursorName] INTO @triggerName, @tableName, @disabled, @insert, @update, @delete;
	END;
	
	CLOSE [cursorName];
	DEALLOCATE [cursorName];
	
	IF EXISTS (SELECT NULL FROM @failures) BEGIN 
		
		SELECT 'The following Errors were Encountered. Please review and correct.' [Deployment Warning!!!];

		SELECT
			[trigger_name],
			[table_name],
			[executed_command],
			[error]
		FROM 
			@failures
		ORDER BY 
			[failure_id];

	END;

	RETURN 0;
GO


-----------------------------------
DROP PROC IF EXISTS dda.list_dynamic_triggers; 
GO 

CREATE PROC dda.list_dynamic_triggers 

AS 
	SET NOCOUNT ON; 

	-- [v0.9.3510.8] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 
	
	SELECT 
		(SELECT QUOTENAME(SCHEMA_NAME(o.[schema_id])) + N'.' + QUOTENAME(OBJECT_NAME(o.[object_id])) FROM sys.objects o WHERE o.[object_id] = t.[parent_id]) [parent_table],
		(SELECT QUOTENAME(SCHEMA_NAME(o.[schema_id])) + N'.' + QUOTENAME(t.[name]) FROM sys.objects o WHERE o.[object_id] = t.[object_id]) [trigger_name],
		(SELECT CASE WHEN EXISTS (SELECT NULL FROM sys.[trigger_events] e WHERE e.[object_id] = t.[object_id] AND [e].[type] = 1) THEN 1 ELSE 0 END) [for_insert],
		(SELECT CASE WHEN EXISTS (SELECT NULL FROM sys.[trigger_events] e WHERE e.[object_id] = t.[object_id] AND [e].[type] = 2) THEN 1 ELSE 0 END) [for_update],
		(SELECT CASE WHEN EXISTS (SELECT NULL FROM sys.[trigger_events] e WHERE e.[object_id] = t.[object_id] AND [e].[type] = 3) THEN 1 ELSE 0 END) [for_delete],
		[t].[is_disabled],
		[t].[create_date],
		[t].[modify_date],
		[t].[object_id] [trigger_object_id],
		[t].[parent_id] [parent_table_id]
	FROM 
		sys.triggers t
		INNER JOIN sys.[extended_properties] p ON t.[object_id] = p.[major_id]
	WHERE 
		p.[name] = N'DDATrigger' AND p.[value] = 'true'
		AND 
			-- don't show the dynamic trigger TEMPLATE - that'll just cause confusion:
			t.[parent_id] <> (SELECT [object_id] FROM sys.objects WHERE [schema_id] = SCHEMA_ID('dda') AND [name] = N'trigger_host');

	RETURN 0;
GO


----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 5. Update version_history with details about current version (i.e., if we got this far, the deployment is successful). 
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DECLARE @CurrentVersion varchar(20) = N'0.9.3510.8';
DECLARE @VersionDescription nvarchar(200) = N'Core Functionality Complete and JSON is schema-compliant.';
DECLARE @InstallType nvarchar(20) = N'Install. ';

IF EXISTS (SELECT NULL FROM dda.[version_history] WHERE CAST(LEFT(version_number, 3) AS decimal(2,1)) >= 4)
	SET @InstallType = N'Update. ';

SET @VersionDescription = @InstallType + @VersionDescription;

-- Add current version info:
IF NOT EXISTS (SELECT NULL FROM dda.version_history WHERE [version_number] = @CurrentVersion) BEGIN
	INSERT INTO dda.version_history (version_number, [description], deployed)
	VALUES (@CurrentVersion, @VersionDescription, GETDATE());
END;
GO

-----------------------------------
SELECT * FROM dda.version_history;
GO
