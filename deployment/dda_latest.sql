/*

		I N S T R U C T I O N S

			INSTALL
				1. RUN. 
				2. CONFIGURE. 
			
			
			UPDATE:
				1. RUN. 
				2. UPDATE. 


			I N S T A L L
				1. RUN
					- Make sure you've opened this script in/against the database you wish to target (i.e., not master, or some other database, etc).
					- Use SECTION 0 if/as needed (you can comment it out or change it - whatever suits your needs). 
					- Once you're connected, in your target database, execute this entire script (i.e., F5). 

				2. CONFIGURE
					- Determine which tables you'd like to EXPLICITLY track for auditing changes (i.e., dda only works against explicitly targeted tables).
						NOTE: 
							- ONLY tables with an explicit PK (constraint) can be audited. (Tables without a PK are 'spreadsheets', even if they live in SQL Server).
							- You can create temporary 'work-arounds' for tables without PKs by adding rows to dda.surrogate_keys. 
							- Attempting to 'tag' a table for auditing without a PK will result in an error - i.e., dda logic will require surrogate keys or a PK. 


					- If you ONLY want to audit a FEW tables, use dda.enable_table_auditing - called 1x per EACH table you wish to audit:

								For example, if you have a [Users] table with an existing PK, you'd run the following: 

											EXEC dda.[enable_table_auditing] 
												@TargetSchema = N'dbo',   -- defaults to dbo if NOT specified (i.e., NOT needed for dbo.owned-tables).
												@TargetTable = N'Users';


								And, if you had an [Events] 'table' without an explicitly defined PK, you could define a SURROGATE key
									as part of the setup process for enabling auditing against this table, like so: 

											EXEC dda.[enable_table_auditing]  
												@TargetTable = N'Events', 
												@SurrogateKeys = N'EventCategory, EventID';  -- DDA will treat these two columns as IF they were an explicit PK (for row Identification).



					- If you want to audit MOST/ALL tables, use dda.enable_database_auditing - called 1x for an entire database - WITH OPTIONS to exclude specific tables. 
						
								For example, assume you have 35 tables in your database - and that you wish to track/audit all but 3 of them: 

												EXEC dda.[enable_database_auditing] 
													@ExcludedTables = N'Calendar, DateDimensions, StaticFields';


								And/or if some of your 35 tables (other than the 3 listed above) do NOT have PKs and you wish to 'skip' them for now (or forever): 


												EXEC dda.[enable_database_auditing] 
													@ExcludedTables = N'Calendar, DateDimensions, StaticFields', 
													@ExcludeTablesWithoutPKs = 1;

										Then, the @ExcludeTablesWithoutPKs parameter will let you skip all tables that CANNOT be audited without either adding a PK or surrogate-key defs. 
											NOTE: if you skip/exclude tables via the @ExcludeTablesWithoutPKs parameter, a report of all skipped tables will be output at the end of execution.

					- for BOTH dda.enable_table_auditing and dda.enable_database_auditing, you CAN specify the format/naming-structure for deployed triggers
						by using the @TriggerNamePattern - which uses the {0} token as a place-holder for your specific table-name. 

								For example:
									- if I have 3 tables in my database: Widgets, Users, and Events
									- and I specify
											@TriggerNamePattern = N'auditing_trigger_for_{0}'

									- then the following trigger names will be applied/created (respectively) for the tables listed above: 
													auditing_trigger_for_Widgets
													auditing_trigger_for_Users
													auditing_trigger_for_Events


			U P D A T E
				1. RUN
					- Make sure you've opened this script in/against the database you wish to target (i.e., not master, or some other database, etc).
					- Use SECTION 0 if/as needed (you can comment it out or change it - whatever suits your needs). 
					- Once you're connected, in your target database, execute this entire script (i.e., F5). 

				2. UPDATE
					- the DDA setup/update script (executed in step 2) will determine if there are new changes (updated logic) for the dda triggers already deployed into your environment. 
						- IF there are NO logic changes available for your deployed/existing triggers, you're done. 
												
						- IF THERE ARE changes, you'll be prompted/alerted to run dda.update_trigger_definitions. 

								BY DEFAULT, execution of this sproc will set @PrintOnly = 1 - meaning it will SHOW you what it WOULD do if executed (@PrintOnlyy = 0). 
								This gives you a chance to visually review which triggers will be updated. 


								Or in other words:
										a. run the following to review changes: 

													EXEC dda.[update_trigger_definitions]

										b. run the following to IMPLEMENT trigger change/updates against all of your deployed triggers: 

													EXEC dda.[update_trigger_definitions] @PrintOnly = 0;

						

		R E F E R E N C E:
			- License, documentation, and source code at: 
				https://github.com/overachiever-productions/dda/


*/


-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 0. Make sure to run the following commands in the database you wish to target for audits (i.e., not master or any other db you might currently be in).
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- 


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

-- v2.0 to v3.0 Update to avoid potential for PK name collisions: 
IF EXISTS (SELECT NULL FROM sys.[indexes] WHERE [object_id] = OBJECT_ID(N'dda.translation_tables') AND [name] = N'PK_translation_tables' AND [is_primary_key] = 1) BEGIN
	EXEC sp_rename N'dda.translation_tables.PK_translation_tables', N'PK_dda_translation_tables';
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

-- v2.0 to v3.0 Update to avoid potential for PK name collisions: 
IF EXISTS (SELECT NULL FROM sys.[indexes] WHERE [object_id] = OBJECT_ID(N'dda.translation_columns') AND [name] = N'PK_translation_columns' AND [is_primary_key] = 1) BEGIN
	EXEC sp_rename N'dda.translation_columns.PK_translation_columns', N'PK_dda_translation_columns';
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
		[translation_value_id] int IDENTITY(1,1) NOT NULL, 
		[table_name] sysname NOT NULL, 
		[column_name] sysname NOT NULL, 
		[key_value] sysname NOT NULL, 
		[translation_value] sysname NOT NULL,
		[target_json_type] tinyint NULL,
		[notes] nvarchar(MAX) NULL,
		CONSTRAINT PK_translation_values PRIMARY KEY NONCLUSTERED ([translation_value_id])
	);

	CREATE UNIQUE CLUSTERED INDEX CLIX_translation_values_by_identifiers ON dda.[translation_values] ([table_name], [column_name], [key_value]);

END;

-- v2.0 to v3.0 correction to PK column name and PK constraint name: 
IF EXISTS (SELECT NULL FROM sys.columns WHERE [object_id] = OBJECT_ID(N'dda.translation_values') AND [name] = N'translation_key_id') BEGIN 
	EXEC sp_rename N'dda.translation_values.PK_translation_keys', N'PK_dda_translation_values';
	EXEC sp_rename N'dda.translation_values.translation_key_id', N'translation_value_id', N'COLUMN';
END;

-- v2.0 to v3.0 removal of 'types' column: 
IF EXISTS (SELECT NULL FROM sys.columns WHERE [object_id] = OBJECT_ID(N'dda.translation_values') AND [name] = N'translation_value_type') BEGIN
	EXEC sp_executesql N'ALTER TABLE [dda].[translation_values] DROP CONSTRAINT [DF_translation_values_translation_value_type]';
	EXEC sp_executesql N'ALTER TABLE [dda].[translation_values] DROP COLUMN [translation_value_type];';
END;

-- v4.2 to v5.0 cough, re-adding types column - but now as target_json_type: 
IF NOT EXISTS (SELECT NULL FROM sys.columns WHERE [object_id] = OBJECT_ID(N'dda.translation_values') AND [name] = N'target_json_type') BEGIN 
	BEGIN TRY
		BEGIN TRANSACTION; 
			CREATE TABLE dda.translation_values_tmp (
				translation_value_id int IDENTITY (1, 1) NOT NULL,
				table_name sysname NOT NULL,
				column_name sysname NOT NULL,
				key_value sysname NOT NULL,
				translation_value sysname NOT NULL,
				target_json_type tinyint NULL,
				notes nvarchar(MAX) NULL 
			);

			IF EXISTS(SELECT NULL FROM [dda].[translation_values]) BEGIN
				SET IDENTITY_INSERT dda.[translation_values_tmp] ON;

				EXEC (
					'INSERT INTO dda.translation_values_tmp (translation_value_id, table_name, column_name, key_value, translation_value, notes)
					 SELECT translation_value_id, table_name, column_name, key_value, translation_value, notes FROM dda.translation_values WITH (TABLOCKX);'
				);

				SET IDENTITY_INSERT dda.[translation_values_tmp] OFF;
			END;

			DROP TABLE dda.translation_values;

			EXECUTE sp_rename N'dda.translation_values_tmp', N'translation_values', 'OBJECT';

			ALTER TABLE dda.translation_values ADD CONSTRAINT PK_dda_translation_values PRIMARY KEY NONCLUSTERED (translation_value_id);

			CREATE UNIQUE CLUSTERED INDEX CLIX_translation_values_by_identifiers ON dda.translation_values (
				table_name,
				column_name,
				key_value
			);

		COMMIT;
	END TRY
	BEGIN CATCH 
		DECLARE @error nvarchar(MAX);
		SELECT @error = N'Terminating DDA Update Script. Fatal Error Encountered. ' + CAST(ERROR_NUMBER() AS sysname) + N' - ' + ERROR_MESSAGE();
		ROLLBACK; 
		RAISERROR(@error, 21, 1) WITH LOG;
	END CATCH;
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
IF OBJECT_ID('dda.translation_keys') IS NULL BEGIN 
	
	CREATE TABLE dda.translation_keys (
		[translation_key_id] int IDENTITY(1,1) NOT NULL, 
		[table_name] sysname NOT NULL, 
		[column_name] sysname NOT NULL, 
		[key_table] sysname NOT NULL, 
		[key_column] sysname NOT NULL, 
		[value_column] sysname NOT NULL, 
		[notes] nvarchar(MAX) NULL,
		CONSTRAINT PK_translation_keys PRIMARY KEY CLUSTERED ([translation_key_id])
	);

END;

DROP TRIGGER IF EXISTS [dda].[rules_for_keys];
GO

CREATE TRIGGER [dda].[rules_for_keys] ON [dda].[translation_keys] FOR INSERT, UPDATE
AS 

	-- NOTE: 
	--		Triggers are UGLY. Using them HERE makes sense given how infrequently they'll be executed. 
	--		In other words, do NOT take use of triggers here as an indication that using triggers to
	--			enforce business rules or logic in YOUR databases is any kind of best practice, as it
	--			almost certainly is NOT a best practice (for anything other than light-weight auditing).

	-- verify that table is in correct format: <schema>.<table>. 
	DECLARE @tableName sysname, @columnName sysname, @keyTable sysname;
	SELECT 
		@tableName = [table_name], 
		@columnName = [column_name], 
		@keyTable = [key_table]
	FROM [Inserted];

	-- Check Naming of @tableName:
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

	-- Check Naming of @keyTable:
	SELECT 
		@dbNamePart = PARSENAME(@keyTable, 3),
		@schemaNamePart = PARSENAME(@keyTable, 2), 
		@tableNamePart = PARSENAME(@keyTable, 1);

	IF @dbNamePart IS NOT NULL BEGIN 
		RAISERROR(N'The [key_table] column MUST be specified in <schema_name>.<db_name> format. Database-name is not supported.', 16, 1);
		ROLLBACK;
		GOTO Finalize;
	END;

	IF @tableNamePart IS NULL BEGIN 
		RAISERROR('The [key_table] column MUST be specified in <schema_name>.<db_name> format.', 16, 1);
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

		RAISERROR('The [key_table] column MUST be specified in <schema_name>.<db_name> format.', 16, 1);
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

-- v2.0 to v3.0 Update to avoid potential for PK name collisions: 
IF EXISTS (SELECT NULL FROM sys.[indexes] WHERE [object_id] = OBJECT_ID(N'dda.surrogate_keys') AND [name] = N'PK_surrogate_keys' AND [is_primary_key] = 1) BEGIN
	EXEC sp_rename N'dda.surrogate_keys.PK_surrogate_keys', N'PK_dda_surrogate_keys';
END;


-----------------------------------
IF OBJECT_ID(N'dda.secondary_keys', N'U') IS NULL BEGIN 
	
	CREATE TABLE dda.secondary_keys ( 
		secondary_id int IDENTITY(1, 1) NOT NULL, 
		[schema] sysname NOT NULL, 
		[table] sysname NOT NULL, 
		[serialized_secondary_columns] nvarchar(260) NOT NULL, 
		[definition_date] datetime CONSTRAINT DF_secondary_keys_definition_date DEFAULT (GETDATE()), 
		[notes] nvarchar(MAX) NULL, 
		CONSTRAINT PK_secondary_keys PRIMARY KEY CLUSTERED ([schema], [table])
	);

END;

-- v2.0 to v3.0 Update to avoid potential for PK name collisions: 
IF EXISTS (SELECT NULL FROM sys.[indexes] WHERE [object_id] = OBJECT_ID(N'dda.secondary_keys') AND [name] = N'PK_secondary_keys' AND [is_primary_key] = 1) BEGIN
	EXEC sp_rename N'dda.secondary_keys.PK_secondary_keys', N'PK_dda_secondary_keys';
END;


-----------------------------------
/*


*/

IF OBJECT_ID('dda.audits', 'U') IS NULL BEGIN

	CREATE TABLE dda.audits (
		[audit_id] int IDENTITY(1,1) NOT NULL,  
		[timestamp] datetime NOT NULL CONSTRAINT DF_data_audit_timestamp DEFAULT (GETDATE()), 
		[schema] sysname NOT NULL, 
		[table] sysname NOT NULL, 
		[original_login] sysname NOT NULL, 
		[executing_user] sysname NOT NULL, 
		[operation] char(9) NOT NULL, 
		[transaction_id] int NULL,
		[row_count] int NOT NULL, 
		[audit] nvarchar(MAX) CONSTRAINT CK_audit_data_data_is_json CHECK (ISJSON([audit]) > 0), 
		CONSTRAINT PK_audits PRIMARY KEY NONCLUSTERED ([audit_id])
	); 

	CREATE CLUSTERED INDEX CLIX_audits_by_timestamp ON dda.[audits] ([timestamp]);

	CREATE NONCLUSTERED INDEX IX_audits_by_original_login ON dda.[audits] ([original_login], [timestamp], [schema], [table]);

	CREATE NONCLUSTERED INDEX IX_audits_by_executing_user ON dda.[audits] ([executing_user], [timestamp], [schema], [table]);

	CREATE NONCLUSTERED INDEX IX_audits_by_table ON dda.[audits] ([schema], [table], [timestamp]);
END;

IF EXISTS (SELECT NULL FROM sys.columns WHERE [object_id] = OBJECT_ID('dda.audits') AND [name] = N'operation' AND [max_length] = 9) BEGIN 
	ALTER TABLE dda.[audits] ALTER COLUMN [operation] char(6) NOT NULL;
END;

-- v2.0 to v3.0 Update to avoid potential for PK name collisions: 
IF EXISTS (SELECT NULL FROM sys.[indexes] WHERE [object_id] = OBJECT_ID(N'dda.audits') AND [name] = N'PK_audits' AND [is_primary_key] = 1) BEGIN
	EXEC sp_rename N'dda.audits.PK_audits', N'PK_dda_audits';
END;

-- v6 changes to account for impersonation:
IF EXISTS (SELECT NULL FROM sys.columns WHERE [object_id] = OBJECT_ID(N'dda.audits') AND [name] = N'user') BEGIN
	CREATE TABLE dda.audits_new (
		[audit_id] int IDENTITY(1,1) NOT NULL,  
		[timestamp] datetime NOT NULL CONSTRAINT DF_data_audit_timestamp_new DEFAULT (GETDATE()), 
		[schema] sysname NOT NULL, 
		[table] sysname NOT NULL, 
		[original_login] sysname NOT NULL, 
		[executing_user] sysname NOT NULL, 
		[operation] char(9) NOT NULL, 
		[transaction_id] int NULL,
		[row_count] int NOT NULL, 
		[audit] nvarchar(MAX) CONSTRAINT CK_audit_data_data_is_json_new CHECK (ISJSON([audit]) > 0), 
		CONSTRAINT PK_audits PRIMARY KEY NONCLUSTERED ([audit_id])
	); 

	CREATE CLUSTERED INDEX CLIX_audits_by_timestamp_new ON dda.[audits_new] ([timestamp]);

	BEGIN TRY 
		BEGIN TRAN;
			SET IDENTITY_INSERT dda.audits_new ON;

				DECLARE @ddlChange nvarchar(MAX) = N'
				INSERT INTO [dda].[audits_new] (
					[audit_id],
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
				SELECT 
					[audit_id]	,
					[timestamp],
					[schema],
					[table],
					[user] [original_login], 
					N''<legacy>'' AS [executing_user],
					[operation],
					[transaction_id],
					[row_count],
					[audit] 
				FROM 
					dda.[audits]; ';

				EXEC sys.sp_executesql @ddlChange;

			SET IDENTITY_INSERT dda.audits_new OFF;

			DROP TABLE [dda].[audits];

			EXEC sp_rename N'dda.audits_new', N'audits';
			EXEC sp_rename N'dda.audits.CLIX_audits_by_timestamp_new', N'CLIX_audits_by_timestamp', N'INDEX';
			EXEC sp_rename N'dda.DF_data_audit_timestamp_new', N'DF_data_audit_timestamp', N'OBJECT';
			EXEC sp_rename N'dda.CK_audit_data_data_is_json_new', N'CK_audit_data_data_is_json', N'OBJECT';

			CREATE NONCLUSTERED INDEX IX_audits_by_original_login ON dda.[audits] ([original_login], [timestamp], [schema], [table]);

			CREATE NONCLUSTERED INDEX IX_audits_by_executing_user ON dda.[audits] ([executing_user], [timestamp], [schema], [table]);

			CREATE NONCLUSTERED INDEX IX_audits_by_table ON dda.[audits] ([schema], [table], [timestamp]);

		COMMIT;
	END TRY
	BEGIN CATCH 
			
	END CATCH;
END;


----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 3. <Placeholder for> Cleanup / Refactor from Previous Versions:
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------


----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 4. Deploy Code.
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------------------------------------
-- Meta-Data and Capture-Related Functions
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
/*

	'Stolen' from S4. 

*/

IF OBJECT_ID('dda.get_engine_version','FN') IS NOT NULL
	DROP FUNCTION dda.get_engine_version;
GO

CREATE FUNCTION dda.get_engine_version() 
RETURNS decimal(4,2)
AS
	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	BEGIN 
		DECLARE @output decimal(4,2);
		
		DECLARE @major sysname, @minor sysname, @full sysname;
		SELECT 
			@major = CAST(SERVERPROPERTY('ProductMajorVersion') AS sysname), 
			@minor = CAST(SERVERPROPERTY('ProductMinorVersion') AS sysname), 
			@full = CAST(SERVERPROPERTY('ProductVersion') AS sysname); 

		IF @major IS NULL BEGIN
			SELECT @major = LEFT(@full, 2);
			SELECT @minor = REPLACE((SUBSTRING(@full, LEN(@major) + 2, 2)), N'.', N'');
		END;

		SET @output = CAST((@major + N'.' + @minor) AS decimal(4,2));

		RETURN @output;
	END;
GO


-----------------------------------
/*


*/

DROP FUNCTION IF EXISTS dda.[split_string];
GO

CREATE FUNCTION [dda].[split_string](@serialized nvarchar(MAX), @delimiter nvarchar(20), @TrimResults bit)
RETURNS @Results TABLE (row_id int IDENTITY NOT NULL, result nvarchar(MAX))
AS 
	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

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
	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

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


-----------------------------------
/*


*/

DROP PROC IF EXISTS dda.[extract_key_columns];
GO

CREATE PROC dda.[extract_key_columns]
	@TargetSchema				sysname				= N'dbo',
	@TargetTable				sysname, 
	@Output						nvarchar(MAX)		= N''	OUTPUT
AS
    SET NOCOUNT ON; 

	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 
	
	DECLARE @columns nvarchar(MAX) = N'';
	DECLARE @objectName sysname = QUOTENAME(@TargetSchema) + N'.' + QUOTENAME(@TargetTable);

	SELECT  
		@columns = @columns + c.[name] + N', '
	FROM 
		sys.[indexes] i 
		INNER JOIN sys.[index_columns] ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id] 
		INNER JOIN sys.columns c ON ic.[object_id] = c.[object_id] AND ic.[column_id] = c.[column_id] 
	WHERE 
		i.[is_primary_key] = 1 
		AND i.[object_id] = OBJECT_ID(@objectName)
	ORDER BY 
		ic.[index_column_id]; 

	IF @columns <> N'' BEGIN 
		SET @columns = LEFT(@columns, LEN(@columns) - 1);
	  END;
	ELSE BEGIN 
		SELECT @columns = [serialized_surrogate_columns] 
		FROM dda.surrogate_keys
		WHERE [schema] = @TargetSchema AND [table] = @TargetTable;
	END;

	IF @Output IS NULL BEGIN 
		SET @Output = @columns;
	  END;
	ELSE BEGIN 
		SELECT @columns [Output]
	END;

	RETURN 0;
GO


-----------------------------------
/*

https://docs.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql?view=sql-server-ver15#return-value
Value of the Type column	JSON data type
0	null
1	string
2	number
3	true/false
4	array
5	object


				
				-- NULLS:
				SELECT dda.[get_json_data_type](NULL);
				SELECT dda.[get_json_data_type]('null'); 
				SELECT dda.[get_json_data_type]('NULL'); -- string


				SELECT dda.[get_json_data_type]('true');
				SELECT dda.[get_json_data_type]('True');  -- string (not boolean)
				SELECT dda.[get_json_data_type](325);
				SELECT dda.[get_json_data_type](325.00);
				SELECT dda.[get_json_data_type](-325);
				SELECT dda.[get_json_data_type](-325.99);
				SELECT dda.[get_json_data_type]('-325.99');
				SELECT dda.[get_json_data_type]('$325');
				SELECT dda.[get_json_data_type]('string here');

				SELECT dda.[get_json_data_type]('2020-10-20T13:48:39.567');
				SELECT dda.[get_json_data_type]('C7A3ED8B-AFE1-41BB-8ED9-F3777DA7D996');     


				SELECT dda.[get_json_data_type]('{
				  "my key $1": {
					"regularKey":{
					  "key with . dot": 1
					}
				  }
				}');


				SELECT dda.[get_json_data_type](N'[
				{
				"OrderNumber":"SO43659",
				"OrderDate":"2011-05-31T00:00:00",
				"AccountNumber":"AW29825",
				"ItemPrice":2024.9940,
				"ItemQuantity":1
				},
				{
				"OrderNumber":"SO43661",
				"OrderDate":"2011-06-01T00:00:00",
				"AccountNumber":"AW73565",
				"ItemPrice":2024.9940,
				"ItemQuantity":3
				}
				]');



*/


IF OBJECT_ID('dda.get_json_data_type','FN') IS NOT NULL
	DROP FUNCTION dda.[get_json_data_type];
GO

CREATE FUNCTION dda.[get_json_data_type] (@value nvarchar(MAX))
RETURNS tinyint
AS
    
	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 
    
    BEGIN; 

		-- 0
		IF @value IS NULL RETURN 0;
		IF @value COLLATE SQL_Latin1_General_CP1_CS_AS = N'null' RETURN 0;
    	
		-- 3  true/false must be lower-case to equate to boolean values - otherwise, it's a string. 
    	IF @value COLLATE SQL_Latin1_General_CP1_CS_AS IN ('true', 'false') RETURN 3;

		-- 2
		IF @value = N'' RETURN 1; 
		IF @value NOT LIKE '%[^0123456789.-]%' RETURN 2; 

		-- 4 & 5
    	IF ISJSON(@value) = 1 BEGIN 
			IF LEFT(LTRIM(@value), 1) = N'[' RETURN 4; 

			RETURN 5;
		END;

    	-- at this point, there's nothing left but string... 
    	RETURN 1;
    
    END;
GO


-----------------------------------
/*

*/

DROP FUNCTION IF EXISTS dda.extract_custom_trigger_logic;
GO

CREATE FUNCTION dda.[extract_custom_trigger_logic](@TriggerName sysname)
RETURNS @output table ([definition] nvarchar(MAX) NULL) 
AS 
	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	BEGIN 
		DECLARE @body nvarchar(MAX); 
		SELECT @body = [definition] FROM sys.[sql_modules] WHERE [object_id] = OBJECT_ID(@TriggerName);

		DECLARE @start int, @end int; 
		SELECT 
			@start = PATINDEX(N'%--~~ ::CUSTOM LOGIC::start%', @body),
			@end = PATINDEX(N'%--~~ ::CUSTOM LOGIC::end%', @body);

		DECLARE @logic nvarchar(MAX);
		SELECT @logic = REPLACE(SUBSTRING(@body, @start, @end - @start), N'--~~ ::CUSTOM LOGIC::start', N'');

		DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10);
		DECLARE @whitespaceOnly sysname = N'%[^ ' + NCHAR(9) + @crlf + N']%';

		IF PATINDEX(@whitespaceOnly, @logic) = 0 SET @logic = NULL;

		INSERT INTO @output (
			[definition]
		)
		VALUES	(
			@logic
		);

		RETURN;
	END;
GO



------------------------------------------------------------------------------------------------------------------------------------------------------
-- DDA Trigger 
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
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

	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

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

		SET @rotateSQL = N'			WITH delete_sums AS (
			SELECT 
				' + @rawKeys + N', 
				HASHBYTES(''SHA2_512'', CONCAT(' + @rawColumnNames + N')) [changesum]
			FROM 
				[#temp_deleted]
		), 
		insert_sums AS (
			SELECT
				' + @rawKeys + N', 
				HASHBYTES(''SHA2_512'', CONCAT(' + @rawColumnNames + N')) [changesum]
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


------------------------------------------------------------------------------------------------------------------------------------------------------
-- Search/View
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
/*
	EXAMPLE Signatures:

			EXEC dda.[get_audit_data]
				@StartTime = '2021-01-01 18:55:05',
				@EndTime = '2021-01-30 18:55:05',
				@TransformOutput = 1,
				@FromIndex = 1, 
				@ToIndex = 20;

			EXEC dda.[get_audit_data]
				@TargetLogins = N'sa, bilbo',
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


CREATE PROC [dda].[get_audit_data]
	@StartTime					datetime		= NULL, 
	@EndTime					datetime		= NULL, 
	@TargetLogins				nvarchar(MAX)	= NULL, 
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
	
	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	SET @TargetLogins = NULLIF(@TargetLogins, N'');
	SET @TargetTables = NULLIF(@TargetTables, N'');		
	SET @TransformOutput = ISNULL(@TransformOutput, 1);

	SET @StartTransactionID = NULLIF(@StartTransactionID, N'');
	SET @EndTransactionID = NULLIF(@EndTransactionID, N'');

	SET @FromIndex = ISNULL(@FromIndex, 1);
	SET @ToIndex = ISNULL(@ToIndex, 100);

	IF @StartTime IS NOT NULL AND @EndTime IS NULL BEGIN 
		SET @EndTime = DATEADD(MINUTE, 2, GETDATE());
	END;

	IF @EndTime IS NOT NULL AND @StartTime IS NULL BEGIN 
		RAISERROR(N'@StartTime MUST be specified if @EndTime is specified. (@StartTime can be specified without @EndTime - and @EndTime will be set to GETDATE().)', 16, 1);
		RETURN - 10;
	END;

	IF (@StartTime IS NULL AND @EndTime IS NULL) AND (@StartAuditID IS NULL) AND (@StartTransactionID IS NULL) BEGIN
		IF @TargetLogins IS NULL AND @TargetTables IS NULL BEGIN 
			RAISERROR(N'Queries against Audit data MUST be constrained - either @StartTime [+ @EndTIme], or @TargetLogins, or @TargetTables or @StartAuditID/@StartTransactionIDs - or a combination of time, table, and user constraints.', 16, 1);
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

	IF @TargetLogins IS NOT NULL BEGIN 
		IF @TargetLogins LIKE N'%,%' BEGIN 
			SET @users  = N'[original_login] IN (';

			SELECT 
				@users = @users + N'''' + [result] + N''', '
			FROM 
				dda.[split_string](@TargetLogins, N',', 1)
			ORDER BY 
				[row_id];

			SET @users = LEFT(@users, LEN(@users) - 1) + N') ';

		  END;
		ELSE BEGIN 
			SET @users = N'[original_login] = ''' + @TargetLogins + N''' ';
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
		[original_login] sysname NOT NULL,
		[operation_type] char(6) NOT NULL,
		[transaction_id] int NOT NULL,
		[row_count] int NOT NULL,
		[change_details] nvarchar(MAX) NULL, 
		[translated_json] nvarchar(MAX) NULL
	);

	INSERT INTO [#raw_data] (
		[x].[row_number],
		[x].[total_rows],
		[x].[audit_id],
		[a].[timestamp],
		[a].[table],
		[a].[original_login],
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
		[a].[original_login],
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
		[original_login],
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


DECLARE @get_audit_data nvarchar(MAX) = N'
ALTER PROC [dda].[get_audit_data]
	@StartTime					datetime		= NULL, 
	@EndTime					datetime		= NULL, 
	@TargetLogins				nvarchar(MAX)	= NULL, 
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
	
	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	SET @TargetLogins = NULLIF(@TargetLogins, N'''');
	SET @TargetTables = NULLIF(@TargetTables, N'''');		
	SET @TransformOutput = ISNULL(@TransformOutput, 1);

	SET @StartTransactionID = NULLIF(@StartTransactionID, N'''');
	SET @EndTransactionID = NULLIF(@EndTransactionID, N'''');

	SET @FromIndex = ISNULL(@FromIndex, 1);
	SET @ToIndex = ISNULL(@ToIndex, 100);

	IF @StartTime IS NOT NULL AND @EndTime IS NULL BEGIN 
		SET @EndTime = DATEADD(MINUTE, 2, GETDATE());
	END;

	IF @EndTime IS NOT NULL AND @StartTime IS NULL BEGIN 
		RAISERROR(N''@StartTime MUST be specified if @EndTime is specified. (@StartTime can be specified without @EndTime - and @EndTime will be set to GETDATE().)'', 16, 1);
		RETURN - 10;
	END;

	IF (@StartTime IS NULL AND @EndTime IS NULL) AND (@StartAuditID IS NULL) AND (@StartTransactionID IS NULL) BEGIN
		IF @TargetLogins IS NULL AND @TargetTables IS NULL BEGIN 
			RAISERROR(N''Queries against Audit data MUST be constrained - either @StartTime [+ @EndTIme], or @TargetLogins, or @TargetTables or @StartAuditID/@StartTransactionIDs - or a combination of time, table, and user constraints.'', 16, 1);
			RETURN -11;
		END;
	END;

	IF @StartTime IS NOT NULL BEGIN 
		IF @StartTime > @EndTime BEGIN
			RAISERROR(N''@StartTime may not be > @EndTime - please check inputs and try again.'', 16, 1);
			RETURN -12;
		END;
	END;

	IF @EndAuditID IS NOT NULL AND (@StartAuditID IS NULL OR @EndAuditID <= @StartAuditID) BEGIN 
		RAISERROR(N''@EndAuditID can only be specified when @StartAuditID has been specified and when @EndAuditID is > @StartAuditID. If you wish to specify just a single AuditID only, use @StartAuditID only.'', 16, 1);
		RETURN -13;
	END;

	IF @EndTransactionID IS NOT NULL AND @StartTransactionID IS NULL BEGIN 
		RAISERROR(N''@EndTransactionID can only be used when @StartTransactionID has been specified. If you wish to specify just a single TransactionID only, use @StartTransactionID only.'', 16, 1);
		RETURN -14;
	END;

	-- Grab matching rows based upon inputs/constraints:
	DECLARE @coreQuery nvarchar(MAX) = N''WITH total AS (
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
'';

	DECLARE @timeFilters nvarchar(MAX) = N'''';
	DECLARE @users nvarchar(MAX) = N'''';
	DECLARE @tables nvarchar(MAX) = N'''';
	DECLARE @auditIdClause nvarchar(MAX) = N'''';
	DECLARE @transactionIdClause nvarchar(MAX) = N'''';
	DECLARE @predicated bit = 0;
	DECLARE @newlineAndTabs sysname = N''
		''; 

	IF @StartTime IS NOT NULL BEGIN 
		SET @timeFilters = N''[timestamp] >= '''''' + CONVERT(sysname, @StartTime, 121) + N'''''' AND [timestamp] <= '''''' + CONVERT(sysname, @EndTime, 121) + N'''''' ''; 
		SET @predicated = 1;
	END;

	IF @TargetLogins IS NOT NULL BEGIN 
		IF @TargetLogins LIKE N''%,%'' BEGIN 
			SET @users  = N''[original_login] IN ('';

			SELECT 
				@users = @users + N'''''''' + [result] + N'''''', ''
			FROM 
				dda.[split_string](@TargetLogins, N'','', 1)
			ORDER BY 
				[row_id];

			SET @users = LEFT(@users, LEN(@users) - 1) + N'') '';

		  END;
		ELSE BEGIN 
			SET @users = N''[original_login] = '''''' + @TargetLogins + N'''''' '';
		END;
		
		IF @predicated = 1 SET @users = @newlineAndTabs + N''AND '' + @users;
		SET @predicated = 1;
	END;

	IF @TargetTables IS NOT NULL BEGIN
		IF @TargetTables LIKE N''%,%'' BEGIN 
			SET @tables = N''[table] IN ('';

			SELECT
				@tables = @tables + N'''''''' + [result] + N'''''', ''
			FROM 
				dda.[split_string](@TargetTables, N'','', 1)
			ORDER BY 
				[row_id];

			SET @tables = LEFT(@tables, LEN(@tables) -1) + N'') '';

		  END;
		ELSE BEGIN 
			SET @tables = N''[table] = '''''' + @TargetTables +'''''' '';  
		END;
		
		IF @predicated = 1 SET @tables = @newlineAndTabs + N''AND '' + @tables;
		SET @predicated = 1;
	END;
	
	IF @StartAuditID IS NOT NULL BEGIN 
		IF @EndAuditID IS NULL BEGIN
			SET @auditIdClause = N''[audit_id] = '' + CAST(@StartAuditID AS sysname);
		  END;
		ELSE BEGIN 
			SET @auditIdClause = N''[audit_id] >= '' + CAST(@StartAuditID AS sysname) + N'' AND [audit_id] <= ''  + CAST(@EndAuditID AS sysname)
		END;

		IF @predicated = 1 SET @auditIdClause = @newlineAndTabs + N''AND '' + @auditIdClause;
		SET @predicated = 1;
	END;

	IF @StartTransactionID IS NOT NULL BEGIN 
		DECLARE @year int, @doy int;
		DECLARE @txDate datetime; 
		DECLARE @startTx int;
		DECLARE @endTx int;
		
		IF @StartTransactionID LIKE N''%-%'' BEGIN 
			SELECT @year = LEFT(@StartTransactionID, 4);
			SELECT @doy = SUBSTRING(@StartTransactionID, 6, 3);
			SET @startTx = TRY_CAST((SELECT [result] FROM dda.[split_string](@StartTransactionID, N''-'', 1) WHERE [row_id] = 3) AS int);

			SET @txDate = CAST(CAST(@year AS sysname) + N''-01-01'' AS datetime);
			SET @txDate = DATEADD(DAY, @doy - 1, @txDate);
		  END;
		ELSE BEGIN 
			IF @TransactionDate IS NOT NULL SET @txDate = @TransactionDate;
			SET @startTx = TRY_CAST(@StartTransactionID AS int);
		END;

		IF @EndTransactionID IS NOT NULL BEGIN 
			IF @EndTransactionID LIKE N''%-%'' BEGIN 
				SET @endTx = TRY_CAST((SELECT [result] FROM dda.[split_string](@EndTransactionID, N''-'', 1) WHERE [row_id] = 3) AS int);
			  END; 
			ELSE BEGIN 
				SET @endTx = TRY_CAST(@EndTransactionID AS int);
			END;

			SET @transactionIdClause = N''([transaction_id] >= '' + CAST(@startTx AS sysname) + N'' AND [transaction_id] <= '' + CAST(@endTx AS sysname);
		  END;
		ELSE BEGIN 
			SET @transactionIdClause = N''([transaction_id] = '' + CAST(@startTx AS sysname);
		END;

		IF @startTx IS NULL BEGIN 
			RAISERROR(N''Invalid @StartTransaction Specified. Specify either the exact (integer) ID from dda.audits.transaction_id OR a formatted dddd-doy-####### value as provided by dda.get_audit_data.'', 16, 1);
			RETURN -80;
		END;

		IF @txDate IS NULL BEGIN 
			RAISERROR(N''Invalid @StartTransaction Specified. Specify either the exact (integer) ID from dda.audits.transaction_id OR a formatted dddd-doy-####### value as provided by dda.get_audit_data.'', 16, 1);
			RETURN -81;
		  END;
		ELSE BEGIN 
			SET @transactionIdClause = @transactionIdClause + N'' AND [timestamp] >= '''''' + CONVERT(sysname, @txDate, 121) + N'''''' AND [timestamp] < '''''' + CONVERT(sysname, DATEADD(DAY, 1, @txDate), 121) + N'''''''';
		END;
		
		SET @transactionIdClause = @transactionIdClause + N'')'';

		IF @predicated = 1 SET @transactionIdClause = @newlineAndTabs + N''AND '' + @transactionIdClause;
		SET @predicated = 1;
	END;

	SET @coreQuery = REPLACE(@coreQuery, N''{TimeFilters}'', @timeFilters);
	SET @coreQuery = REPLACE(@coreQuery, N''{Users}'', @users);
	SET @coreQuery = REPLACE(@coreQuery, N''{Tables}'', @tables);
	SET @coreQuery = REPLACE(@coreQuery, N''{AuditID}'', @auditIdClause);
	SET @coreQuery = REPLACE(@coreQuery, N''{TransactionID}'', @transactionIdClause);
	
	DECLARE @coreJSON nvarchar(MAX);
	EXEC sp_executesql 
		@coreQuery, 
		N''@FromIndex int, @ToIndex int, @coreJSON nvarchar(MAX) OUTPUT'', 
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
		[original_login] sysname NOT NULL,
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
		[a].[original_login],
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
		[a].[schema] + N''.'' + [a].[table] [table],
		[a].[original_login],
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
			N''['' + [r].[Value] + N'']'' [change_details]  /* NOTE: without [surrounding brackets], shred no-worky down below... */
		FROM 
			[#raw_data] x 
			CROSS APPLY OPENJSON(JSON_QUERY([x].[change_details], N''$'')) r 
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
			N''key'' [node_type],
			[x].[source_table],
			[x].[change_details] [parent_json],
			[z].[Value] [current_json],
			[y].[Key] [original_column],
			ISNULL([y].[Value], N''null'') [original_value],
			[y].[Type] [original_value_type]
		FROM 
			[#scalar] x 
			OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], N''$[0].key''), N''$'') z 
			CROSS APPLY OPENJSON([z].[Value], N''$'') y
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
			N''detail'' [node_type],
			[x].[source_table],
			[x].[change_details] [parent_json],
			[z].[Value] [current_json],
			[y].[Key] [original_column],
			ISNULL([y].[Value], N''null'') [original_value],
			[y].[Type] [original_value_type]
		FROM 
			[#scalar] x 
			OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], N''$[0].detail''), N''$'') z 
			CROSS APPLY OPENJSON([z].[Value], N''$'') y
		WHERE 
			[y].[Value] NOT LIKE ''%from":%"to":%''
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
		N''detail'' [node_type],
		[x].[source_table],
		[x].[change_details] [parent_json],
		[z].[Value] [current_json],
		[y].[Key] [original_column],
		ISNULL([y].[Value], N''null'') [original_value],
		[y].[Type] [original_value_type]
	INTO 
		#updates
	FROM 
		[#scalar] x 
		OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], N''$[0].detail''), N''$'') z 
		CROSS APPLY OPENJSON([z].[Value], N''$'') y
	WHERE 
		[y].[Type] = 5 AND
		[y].[Value] LIKE ''%from":%"to":%''
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
			ISNULL([y].[Value], N''null'') [original_value], 
			[y].[Type] [original_value_type]
		FROM 
			[#updates] x
			CROSS APPLY OPENJSON([x].[original_value], N''$'') y
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
		
			SET @translationSql = N''INSERT INTO #translation_key_values ([source_table], [source_column], [translation_key], [translation_value]) 
				SELECT @sourceTable [source_table], @sourceColumn [source_column], '' + QUOTENAME(@translationKey) + N'' [translation_key], '' + QUOTENAME(@translationValue) + N'' [translation_value] 
				FROM 
					'' + @translationTable + N'';''

			EXEC sp_executesql 
				@translationSql, 
				N''@sourceTable sysname, @sourceColumn sysname'', 
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
	SELECT DISTINCT /*  TODO: tired... not sure why I''m tolerating this code-smell/nastiness - but need to address it... */
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
		[node_type] IN (N''from'', N''to'');

	WITH [froms] AS ( 
		SELECT 
			[x].[column_name],
			[x].[row_number],
			[x].[json_row_id],
			CASE WHEN [x].[value_type] = 1 THEN STRING_ESCAPE([x].[value], ''json'') ELSE [x].[value] END [value], 
			[x].[value_type],
			[x].[node_id] 
		FROM 
			[#parts] x
		WHERE 
			[node_type] = N''from''
	), 
	[tos] AS ( 
		SELECT 
			[x].[column_name],
			[x].[row_number],
			[x].[json_row_id],
			CASE WHEN [x].[value_type] = 1 THEN STRING_ESCAPE([x].[value], ''json'') ELSE [x].[value] END [value],
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
			N''"'' + [f].[column_name] + N''":{"from":'' + CASE WHEN [f].[value_type] = 1 THEN N''"'' + [f].[value] + N''"'' ELSE [f].[value] END + '',"to":'' + CASE WHEN [t].[value_type] = 1 THEN N''"'' + [t].[value] + N''"'' ELSE [t].[value] END + N''}'' [collapsed]
		FROM 
			[froms] f 
			INNER JOIN [tos] t ON f.[row_number] = t.[row_number] AND f.[json_row_id] = t.[json_row_id] AND f.[column_name] = t.[column_name]
	), 
	[aggregated] AS ( 
		SELECT 
			[row_number],
			[json_row_id],
			N''{'' +
				STRING_AGG([collapsed], N'','') WITHIN GROUP (ORDER BY [row_number], [json_row_id], [node_id]) +
			N''}'' [detail]
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
		[original_value] = CASE WHEN [original_value_type] = 1 THEN STRING_ESCAPE([original_value], ''json'') ELSE [original_value] END, 
		[translated_value] = CASE WHEN [translated_value_type] = 1 THEN STRING_ESCAPE([translated_value], ''json'') ELSE [translated_value] END
	WHERE 
		ISNULL([translated_value_type], [original_value_type]) = 1; 

	/* Serialize Details (for non UPDATEs - they''ve already been handled above) */
	WITH [flattened] AS ( 
		SELECT 
			[row_number], 
			[json_row_id], 
			[node_id],
			N''"'' + ISNULL([translated_column], [original_column]) + N''":'' + CASE WHEN ISNULL([translated_value_type], [original_value_type]) = 1 THEN N''"'' + ISNULL([translated_value], [original_value]) + N''"'' ELSE ISNULL([translated_value], [original_value]) END [collapsed]
		FROM 
			[#nodes] 
		WHERE 
			[node_type] = N''detail''
	), 
	[aggregated] AS ( 
		SELECT 
			[row_number],
			[json_row_id], 
			N''{'' + 
				STRING_AGG([collapsed], N'','') WITHIN GROUP (ORDER BY [row_number], [json_row_id], [node_id]) +
			N''}'' [detail]
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
			N''"'' + ISNULL([translated_column], [original_column]) + N''":'' + CASE WHEN ISNULL([translated_value_type], [original_value_type]) = 1 THEN N''"'' + ISNULL([translated_value], [original_value]) + N''"'' ELSE ISNULL([translated_value], [original_value]) END [collapsed]
		FROM 
			[#nodes] 
		WHERE 
			[node_type] = N''key''
	),
	[aggregated] AS ( 
		SELECT 
			[row_number],
			[json_row_id], 
			N''{'' + 
				STRING_AGG([collapsed], N'','') WITHIN GROUP (ORDER BY [row_number], [json_row_id], [node_id]) +
			N''}'' [keys]
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
	 	x.[translated_json] = N''[{"key":['' + s.[translate_keys] + N''],"detail":['' + s.[translated_details] + N'']}]''
	FROM 
		[#raw_data] x 
		INNER JOIN [#scalar] s ON [x].[row_number] = [s].[row_number]
	WHERE 
		x.[row_count] = 1;

	WITH [flattened] AS ( 
		SELECT 
			[row_number], 
			N''['' +
				STRING_AGG(N''{"key":['' + [translate_keys] + N''],"detail":['' + [translated_details] + N'']}'', N'','') WITHIN GROUP(ORDER BY [row_number], [json_row_id]) + 
			N'']'' [collapsed]
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
		[original_login],
		ISNULL([translated_table], [table]) [table],
		CONCAT(DATEPART(YEAR, [timestamp]), N''-'', RIGHT(N''000'' + DATENAME(DAYOFYEAR, [timestamp]), 3), N''-'', RIGHT(N''000000000'' + CAST([transaction_id] AS sysname), 9)) [transaction_id],
		[operation_type],
		[row_count],
		CASE WHEN [translated_json] IS NULL AND [change_details] LIKE N''%,"dump":%'' THEN [change_details] ELSE ISNULL([translated_json], [change_details]) END [change_details] 
	FROM 
		[#raw_data]
	ORDER BY 
		[row_number];

	RETURN 0;

 ';

IF (SELECT dda.get_engine_version())> 14.0  
	EXEC sp_executesql @get_audit_data;

------------------------------------------------------------------------------------------------------------------------------------------------------
-- Utilities:
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
DROP PROC IF EXISTS dda.list_dynamic_triggers; 
GO 

CREATE PROC dda.list_dynamic_triggers 

AS 
	SET NOCOUNT ON; 

	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	WITH core AS ( 
		SELECT 
			(SELECT QUOTENAME(SCHEMA_NAME(o.[schema_id])) + N'.' + QUOTENAME(OBJECT_NAME(o.[object_id])) FROM sys.objects o WHERE o.[object_id] = t.[parent_id]) [parent_table],
			(SELECT QUOTENAME(SCHEMA_NAME(o.[schema_id])) + N'.' + QUOTENAME(t.[name]) FROM sys.objects o WHERE o.[object_id] = t.[object_id]) [trigger_name],
			CAST(p.[value] AS sysname) [trigger_version],
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
			p.[name] = N'DDATrigger' AND p.[value] IS NOT NULL
			AND 
				-- don't show the dynamic trigger TEMPLATE - that'll just cause confusion:
				t.[parent_id] <> (SELECT [object_id] FROM sys.objects WHERE [schema_id] = SCHEMA_ID('dda') AND [name] = N'trigger_host')
	) 
	
	SELECT 
		c.[parent_table],
		c.[trigger_name],
		c.[trigger_version],
		x.[definition] [custom_trigger_logic],
		c.[for_insert],
		c.[for_update],
		c.[for_delete],
		c.[is_disabled],
		c.[create_date],
		c.[modify_date],
		c.[trigger_object_id],
		c.[parent_table_id]
	FROM 
		[core] c
		CROSS APPLY dda.[extract_custom_trigger_logic](c.[trigger_name]) x

	RETURN 0;
GO


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

	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

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
		RAISERROR(N'Target Table %s already has a dynamic data auditing (DDA) trigger defined. Please review existing triggers on table.', 16, 1, @objectName);
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

		RAISERROR(N'Target Table %s does NOT have an Explicit Primary Key defined - nor were @SurrogateKeys provided for configuration/setup.', 16, 1, @objectName);
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

		DECLARE @latestVersion sysname;
		SELECT @latestVersion = [version_number] FROM dda.version_history WHERE [version_id] = (SELECT MAX(version_id) FROM dda.version_history);

		-- mark the trigger as a DDAT:
		EXEC [sys].[sp_addextendedproperty]
			@name = N'DDATrigger',
			@value = @latestVersion,
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
/*
	SIGNATURE:
		EXEC [dda].[enable_database_auditing] 
			@ExcludedTables = N'dbo.shredded, dda.another_table, [dbo].[_SCSActivities], [dbo].[HomeSlice]  ', 
			@ExcludeTablesWithoutPKs = 1,
			@ContinueOnError = 1;

*/

IF OBJECT_ID('dda.enable_database_auditing','P') IS NOT NULL
	DROP PROC dda.[enable_database_auditing];
GO

CREATE PROC dda.[enable_database_auditing]
	@ExcludedTables				nvarchar(MAX)			= NULL, 
	@ExcludedSchemas			nvarchar(MAX)			= NULL,			-- wildcards NOT allowed/supported.
	@ExcludeTablesWithoutPKs	bigint					= 0,			-- Default behavior is to throw an error/warning - and stop. 
	@TriggerNamePattern			sysname					= N'ddat_{0}', 
	@ContinueOnError			bit						= 1,
	@PrintOnly					bit						= 0
AS
    SET NOCOUNT ON; 

	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 
	
	SET @ExcludedTables = NULLIF(@ExcludedTables, N'');
	SET @ExcludedSchemas = NULLIF(@ExcludedSchemas, N'');
	SET @TriggerNamePattern = ISNULL(NULLIF(@TriggerNamePattern, N''), N'ddat_{0}');
	SET @ExcludeTablesWithoutPKs = ISNULL(@ExcludeTablesWithoutPKs, 0);
	SET @ContinueOnError = ISNULL(@ContinueOnError, 1);
	SET @PrintOnly = ISNULL(@PrintOnly, 0);

	-- check for tables without PKs (that aren't in the list of exclusions):
	DECLARE @exclusions table (
		[row_id] int NOT NULL, 
		[schema_name] sysname NULL,
		[table_name] sysname NOT NULL
	);

	INSERT INTO @exclusions (
		[row_id],
		[table_name]
	)
	SELECT 
		[row_id], 
		[result]
	FROM 
		dda.[split_string](@ExcludedTables, N',', 1);

	IF EXISTS (SELECT NULL FROM @exclusions) BEGIN
		UPDATE @exclusions 
		SET 
			[schema_name] = ISNULL(PARSENAME([table_name], 2), N'dbo'), 
			[table_name] = PARSENAME([table_name], 1);
	END;

	DECLARE @schemasToExclude table ( 
		row_id int IDENTITY(1,1) NOT NULL, 
		[name] sysname NOT NULL 
	);

	IF @ExcludedSchemas IS NOT NULL BEGIN 
		INSERT INTO @schemasToExclude (
			[name]
		)
		SELECT 
			[result] [name]
		FROM 
			dda.[split_string](@ExcludedSchemas, N',', 1)
		ORDER BY 
			[row_id];
	END;

	DECLARE @nonExcludedTablesWithoutPKs table (
		[table_id] int IDENTITY(1,1) NOT NULL, 
		[schema_name] sysname NOT NULL, 
		[table_name] sysname NOT NULL
	);

	INSERT INTO @nonExcludedTablesWithoutPKs (
		[schema_name],
		[table_name]
	)
	SELECT 
		SCHEMA_NAME([t].[schema_id]) [schema_name],
		[t].[name] [table_name]
	FROM 
		sys.[tables] [t]
		LEFT OUTER JOIN @exclusions [e] ON SCHEMA_NAME([t].[schema_id]) = [e].[schema_name] AND [t].[name] = [e].[table_name]
	WHERE 
		[type] = N'U'
		AND OBJECTPROPERTYEX([object_id], N'TableHasPrimaryKey') = 0
		AND [e].[table_name] IS NULL;

	DELETE x 
	FROM 
		@nonExcludedTablesWithoutPKs x 
		LEFT OUTER JOIN dda.[surrogate_keys] k ON [x].[schema_name] = k.[schema] AND x.[table_name] = k.[table]
	WHERE
		[k].[surrogate_id] IS NOT NULL;

	-- yeah... don't fail things cuz of this guy:
	DELETE FROM @nonExcludedTablesWithoutPKs WHERE [schema_name] = N'dda' AND [table_name] = N'trigger_host';

	DECLARE @serializedNonPKTables nvarchar(MAX) = N'';
	IF EXISTS (SELECT NULL FROM @nonExcludedTablesWithoutPKs) BEGIN 
		SELECT 
			@serializedNonPKTables	= @serializedNonPKTables + QUOTENAME([schema_name]) + N'.' + QUOTENAME([table_name]) + N' 
		'  -- INTENTIONAL carriage return (and 2x TAB chars) = cheat/hack for formatting output below (and work on BOTH Windows and Linux).
		FROM 
			@nonExcludedTablesWithoutPKs 
		ORDER BY 
			[table_id];

		SET @serializedNonPKTables = LEFT(@serializedNonPKTables, LEN(@serializedNonPKTables) - 4);

		IF @ExcludeTablesWithoutPKs = 0 BEGIN
			PRINT N'ERROR:';
			PRINT N'	Tables without Primary Keys were detected and were NOT EXCLUDED from processing.';
			PRINT N'		Each table to be audited must EITHER have an explicit Primary Key - or a ''work-around''/surrogate key.';
			PRINT N'';
			PRINT N'	The following tables do NOT have Primary Keys and were NOT excluded from processing:';
			PRINT N'		' + @serializedNonPKTables;
			PRINT N'';
			PRINT N'';
			PRINT N'	To continue, do ONE OR MORE of the following: ';
			PRINT N'		- [RECOMMENDED]: Add Primary Keys to all tables listed above. ';
			PRINT N'		- [WORK-AROUND]: Add surrogate ''keys'' for any of the tables above to the dda.surrogate_keys table ';
			PRINT N'				where a PK might not currently make sense.';
			PRINT N'		- [WORK-AROUND]: Explicitly exclude any of the tables listed above via the @ExcludedTables parameter - for any ';
			PRINT N'				tables you do NOT wish to track changes against (i.e., those without a PK or surrogate key defined.';
			PRINT N'					EXAMPLE: @ExcludedTables = N''dbo.someTableHere, dbo.AnotherTableHere, etc.'' -- (schema-names optional).';
			PRINT N'		- [WORK-AROUND]: Set @ExcludeTablesWithoutPKs = 1 - and all tables without a PK will be skipped during processing.';
			PRINT N'				NOTE: a list of non-tracked tables WILL be output at the end of processing/execution.';
			PRINT N'';
			PRINT N'';

			RETURN 0;
		END;
	END;

	-- If we're still here, all tables either have FKs, surrogates, or have been explicitly or 'auto' excluded - i..e, time to add triggers:
	CREATE TABLE #tablesToAudit (
		row_id	int IDENTITY(1,1) NOT NULL, 
		[object_id] int NOT NULL, 
		[schema_name] sysname NOT NULL, 
		[table_name] sysname NOT NULL, 
		[existing_trigger] sysname NULL, 
		[existing_version] sysname NULL, -- vNEXT: populate this and use it to inform 'callers' or any version 'discrepencies'. 
		[is_disabled] bit NOT NULL DEFAULT (0),
		[is_not_insert_update_deleted] bit NOT NULL DEFAULT (0),
		[error_details] nvarchar(MAX) NULL 
	);

	INSERT INTO [#tablesToAudit] (
		[object_id],
		[schema_name],
		[table_name]
	)
	SELECT 
		[object_id], 
		SCHEMA_NAME([schema_id]) [schema_name],
		[name] [table_name]
	FROM 
		sys.[objects]
	WHERE 
		[type] = 'U'
		AND SCHEMA_NAME([schema_id]) <> 'dda'
	ORDER BY 
		[name];

	DELETE x 
	FROM 
		[#tablesToAudit] x 
		LEFT OUTER JOIN (
			SELECT 
				[row_id] [id],
				[schema_name], 
				[table_name]
			FROM 
				@exclusions

			UNION

			SELECT 
				[table_id] [id], 
				[schema_name], 
				[table_name]
			FROM 
				@nonExcludedTablesWithoutPKs

		) exclusions ON [x].[schema_name] = [exclusions].[schema_name] AND [x].[table_name] = [exclusions].[table_name]
	WHERE 
		-- Exclude DDA tables:
		(x.[schema_name] = N'dda' AND (x.[table_name] = N'trigger_host' OR x.[table_name] = N'audits'))
		OR [exclusions].[id] IS NOT NULL;

	DELETE FROM [#tablesToAudit]
	WHERE 
		[schema_name] IN (SELECT [name] FROM @schemasToExclude);

	-- flag/remove tables already enabled for auditing:
	WITH core AS (  -- NOTE: this is a DRY violation - from dda.list_dynamic_triggers
		SELECT 
			(SELECT SCHEMA_NAME(o.[schema_id]) + N'.' + OBJECT_NAME(o.[object_id]) FROM sys.objects o WHERE o.[object_id] = t.[parent_id]) [parent_table],
			(SELECT QUOTENAME(SCHEMA_NAME(o.[schema_id])) + N'.' + QUOTENAME(t.[name]) FROM sys.objects o WHERE o.[object_id] = t.[object_id]) [trigger_name],
			(SELECT CASE WHEN EXISTS (SELECT NULL FROM sys.[trigger_events] e WHERE e.[object_id] = t.[object_id] AND [e].[type] = 1) THEN 1 ELSE 0 END) [for_insert],
			(SELECT CASE WHEN EXISTS (SELECT NULL FROM sys.[trigger_events] e WHERE e.[object_id] = t.[object_id] AND [e].[type] = 2) THEN 1 ELSE 0 END) [for_update],
			(SELECT CASE WHEN EXISTS (SELECT NULL FROM sys.[trigger_events] e WHERE e.[object_id] = t.[object_id] AND [e].[type] = 3) THEN 1 ELSE 0 END) [for_delete],
			[t].[is_disabled]
		FROM 
			sys.triggers t
			INNER JOIN sys.[extended_properties] p ON t.[object_id] = p.[major_id]
		WHERE 
			p.[name] = N'DDATrigger' AND p.[value] = 'true'
			AND 
				t.[parent_id] <> (SELECT [object_id] FROM sys.objects WHERE [schema_id] = SCHEMA_ID('dda') AND [name] = N'trigger_host')
	)
	
	UPDATE x 
	SET 
		x.[existing_trigger] = t.[trigger_name], 
		x.[is_disabled] = t.[is_disabled], 
		x.[is_not_insert_update_deleted] = t.[is_non_standard]
	FROM 
		[#tablesToAudit] x 
		INNER JOIN (
			SELECT 
				PARSENAME([parent_table], 2) [schema_name],
				PARSENAME([parent_table], 1) [table_name],
				[trigger_name], 
				[is_disabled], 
				CASE 
					WHEN [for_insert] = 0 OR [for_update] = 0 OR [for_delete] = 0 THEN 1
					ELSE 0 
				END [is_non_standard]
			FROM 
				core
		) t ON [x].[schema_name] = [t].[schema_name] AND [x].[table_name] = [t].[table_name];

	DECLARE @row_id int, @schemaName sysname, @tableName sysname; 
	DECLARE @outcome int; 
	DECLARE @error nvarchar(MAX);

	DECLARE [cursorName] CURSOR LOCAL FAST_FORWARD FOR 
	SELECT 
		[row_id], 
		[schema_name], 
		[table_name]
	FROM 
		[#tablesToAudit] 
	WHERE 
		[existing_trigger] IS NULL
	ORDER BY 
		[row_id];
	
	OPEN [cursorName];
	FETCH NEXT FROM [cursorName] INTO @row_id, @schemaName, @tableName;
	
	WHILE @@FETCH_STATUS = 0 BEGIN

		IF @PrintOnly = 1 BEGIN 
			PRINT '... processing for ' + QUOTENAME(@schemaName) + N'.' + QUOTENAME(@tableName) + N' would happen here (@PrintOnly = 1) ....';
		  END; 
		ELSE BEGIN 
			BEGIN TRY 
				BEGIN TRAN;
					SET @outcome = 0;

					EXEC @outcome = dda.[enable_table_auditing] 
						@TargetSchema = @schemaName, 
						@TargetTable = @tableName, 
						@TriggerNamePattern = @TriggerNamePattern, 
						@PrintOnly = 0;

					IF @outcome <> 0 
						RAISERROR('Unexpected Error. No exceptions detected, but execution of dda.enable_table_auditing did NOT RETURN 0.', 16, 1);
				COMMIT;

			END TRY 
			BEGIN CATCH 
				SELECT @error = ERROR_MESSAGE();

				IF @@TRANCOUNT > 0 ROLLBACK;

				UPDATE [#tablesToAudit]
				SET 
					[error_details] = @error 
				WHERE 
					[row_id] = @row_id;

				IF @ContinueOnError = 0 BEGIN 
					RAISERROR('Processing Error Encountered. Excution/Addition of triggers terminated.', 16, 1);
					GOTO Reporting;
				END;

			END CATCH;
		END;
	
		FETCH NEXT FROM [cursorName] INTO @row_id, @schemaName, @tableName;
	END;
	
	CLOSE [cursorName];
	DEALLOCATE [cursorName];

Reporting:
	IF @PrintOnly = 1 BEGIN 
		PRINT N'';
	END;

	IF OBJECT_ID(N'tempdb..#tablesToAudit') IS NOT NULL AND EXISTS (SELECT NULL FROM [#tablesToAudit] WHERE [error_details] IS NOT NULL) BEGIN 
		
		RAISERROR('Errors were encountered during execution.', 16, 1);
		PRINT N'ERROR:'; 
		PRINT N'	The following errors occured:'; 
		PRINT N'';

		-- bletch, cursors are ugly, but: 
		DECLARE [walker] CURSOR LOCAL FAST_FORWARD FOR 
		SELECT 
			[schema_name], 
			[table_name], 
			[error_details]
		FROM 
			[#tablesToAudit] 
		WHERE 
			[error_details] IS NOT NULL
		ORDER BY 
			[row_id];
		
		OPEN [walker];
		FETCH NEXT FROM [walker] INTO @schemaName, @tableName, @error;
		
		WHILE @@FETCH_STATUS = 0 BEGIN
		
			PRINT N'		' + QUOTENAME(@schemaName) + N'.' + QUOTENAME(@tableName);
			PRINT N'			' + @error;
		
			FETCH NEXT FROM [walker] INTO @schemaName, @tableName, @error;
		END;
		
		CLOSE [walker];
		DEALLOCATE [walker];

		PRINT N'';

	END;	

	IF OBJECT_ID(N'tempdb..#tablesToAudit') IS NOT NULL AND EXISTS (SELECT NULL FROM [#tablesToAudit] WHERE [existing_trigger] IS NOT NULL) BEGIN 
		DECLARE @triggerName sysname;
		DECLARE @isDisabled bit; 
		DECLARE @isNonStandard bit;

		PRINT N'NOTE:';
		PRINT N'';
		PRINT N'	The following tables ALREADY have/had dynamic triggers defined (and were SKIPPED):';
		PRINT N'';

		-- bletch, cursors are ugly, but: 
		DECLARE [walker] CURSOR LOCAL FAST_FORWARD FOR 
		SELECT 
			[schema_name], 
			[table_name], 
			[existing_trigger], 
			[is_disabled], 
			[is_not_insert_update_deleted]
		FROM 
			[#tablesToAudit] 
		WHERE 
			[existing_trigger] IS NOT NULL 
		ORDER BY 
			[row_id];
		
		OPEN [walker];
		FETCH NEXT FROM [walker] INTO @schemaName, @tableName, @triggerName, @isDisabled, @isNonStandard;
		
		WHILE @@FETCH_STATUS = 0 BEGIN
		
			PRINT N'		' + QUOTENAME(@schemaName) + N'.' + QUOTENAME(@tableName) + N' -> ' + @triggerName;

			IF @isDisabled = 1 BEGIN 
				PRINT N'			WARNING: Trigger ' + @triggerName + N' IS currently DISABLED.';
			END;


			IF @isNonStandard = 1 BEGIN
				PRINT N'			NOTE: Trigger ' + @triggerName + N' IS _NOT_ configured for ALL operation types (INSERT, UPDATE, DELETE - i.e., one or more operations is NOT enabled).'

			END;

			FETCH NEXT FROM [walker] INTO @schemaName, @tableName, @triggerName, @isDisabled, @isNonStandard;
		END;
		
		CLOSE [walker];
		DEALLOCATE [walker];

		PRINT N'';
		PRINT N'	To UPDATE code within existing dynamic triggers, use dda.update_trigger_definitions.';
		PRINT N'';

	END;
	
	IF EXISTS (SELECT NULL FROM @exclusions) BEGIN 
		DECLARE @serializedExclusions nvarchar(MAX) = N'';

		SELECT 
			@serializedExclusions = @serializedExclusions +  QUOTENAME([schema_name]) + N'.' + QUOTENAME([table_name]) + N' 
		'  -- INTENTIONAL carriage return (and 2x TAB chars) = cheat/hack for formatting output below (and work on BOTH Windows and Linux).
		FROM 
			@exclusions;

		SET @serializedExclusions = LEFT(@serializedExclusions, LEN(@serializedExclusions) - 4);

		PRINT N'NOTE:';
		PRINT N'	The following tables were EXPLICITLY excluded from processing, and have not been enabled for auditing:';
		PRINT N'		' + @serializedExclusions; 
		PRINT N'';

	END;

	IF NULLIF(@serializedNonPKTables, N'') IS NOT NULL BEGIN 
		PRINT N'NOTE: ';
		PRINT N'	The following tables DO NOT have Primary Keys defined and were not EXPLICITLY excluded from auditing: ';
		PRINT N'		' + @serializedNonPKTables;
		PRINT N'';
		PRINT N'	Please review the tables listed above, and if you wish to audit any of them, either add PKs, define a surrogate ';
		PRINT N'		set of keys via INSERTs into dda.surrogate_keys, then re-run execution/deployment.';
		PRINT N'';
	END;

	RETURN 0;
GO


-----------------------------------
-- PICKUP/NEXT: (down on lines 100+ish)

DROP PROC IF EXISTS dda.update_trigger_definitions; 
GO 

CREATE PROC dda.update_trigger_definitions 
	@PrintOnly				bit				= 1, 			-- default to NON-modifying execution (i.e., require explicit change to modify).
	@ForceUpdates			bit				= 0				-- by default, update_trigger_definitions SKIPS anything already AT the target version # ... @ForceUpdates forces logic overwrite/updates ALWAYS.
AS 
	SET NOCOUNT ON; 

	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	-- load definition for the NEW trigger:
	DECLARE @definitionID int; 
	DECLARE @definition nvarchar(MAX); 
	
	SELECT @definitionID = [object_id] FROM sys.[triggers] WHERE [name] = N'dynamic_data_auditing_trigger_template' AND [parent_id] = OBJECT_ID('dda.trigger_host');

	IF @definitionID IS NULL BEGIN 
		-- guessing the chances of this are UNLIKELY (i.e., can't see, say, this SPROC existing but the trigger being gone?), but...still, need to account for this. 
		RAISERROR(N'Dynamic Data Auditing Trigger Template NOT found against table dda.trigger_host. Please re-deploy core DDA plumbing before continuing.', 16, -1);
		RETURN -32; 
	END;

	SELECT @definition = [definition] FROM sys.[sql_modules] WHERE [object_id] = @definitionID;
	DECLARE @pattern nvarchar(MAX) = N'%FOR INSERT, UPDATE, DELETE%';
	DECLARE @custTriggerMarkerStart sysname = N'--~~ ::CUSTOM LOGIC::start', @custTriggerMarkerEnd sysname = N'--~~ ::CUSTOM LOGIC::end';
	DECLARE @bodyStart int = PATINDEX(@pattern, @definition);

	DECLARE @body nvarchar(MAX) = SUBSTRING(@definition, @bodyStart, LEN(@definition) - @bodyStart);

	IF @PrintOnly = 1 BEGIN 
		PRINT N'/* ------------------------------------------------------------------------------------------------------------------';
		PRINT N'';
		PRINT N'	NOTE: ';
		PRINT N'		The @PrintOnly parameter for this stored procedure defaults to a value of 1.';
		PRINT N'			Or, in other words, by DEFAULT, this procedure will NOT modify existing triggers.';
		PRINT N'			INSTEAD, it displays which changes it WOULD make - if executed otherwise.';
		PRINT N'';
		PRINT N'		To execute changes (after you''ve reviewed them), explicitly set @PrintOnly = 0. ';
		PRINT N'			EXAMPLE: ';
		PRINT N'				EXEC dda.update_trigger_definitions @PrintOnly = 0;'
		PRINT N'';
		PRINT N'---------------------------------------------------------------------------------------------------------------------';
		PRINT N'*/'
		PRINT N'';
		PRINT N'';

	END;

	CREATE TABLE #dynamic_triggers (
		[parent_table] nvarchar(260) NULL,
		[trigger_name] nvarchar(260) NULL,
		[trigger_version] sysname NULL,
		[custom_trigger_logic] nvarchar(MAX) NULL,
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
		[trigger_version],
		[custom_trigger_logic],
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

	DECLARE @triggerName sysname, @tableName sysname, @triggerVersion sysname;
	DECLARE @disabled bit, @insert bit, @update bit, @delete bit;
	DECLARE @triggerSchemaName sysname, @triggerTableName sysname, @triggerNameOnly sysname;
	
	DECLARE @latestVersion sysname;
	SELECT @latestVersion = [version_number] FROM dda.version_history WHERE [version_id] = (SELECT MAX(version_id) FROM dda.version_history);
	
	DECLARE @firstAs int = PATINDEX(N'%AS%', @body);
	SET @body = SUBSTRING(@body, @firstAs, LEN(@body) - @firstAs);

	DECLARE @customLogicStart int, @customLogicEnd int;
	SELECT 
		@customLogicStart = PATINDEX(N'%' + @custTriggerMarkerStart + N'%', @body), 
		@customLogicEnd = PATINDEX(N'%' + @custTriggerMarkerEnd + N'%', @body) + LEN(@custTriggerMarkerEnd);

	DECLARE @customLogicPlaceHolder nvarchar(MAX) = SUBSTRING(@body, @customLogicStart, @customLogicEnd - @customLogicStart);

	DECLARE @scope sysname;
	DECLARE @scopeCount int;
	DECLARE @directive nvarchar(MAX);
	DECLARE @currentCustomTriggerLogic nvarchar(MAX);
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
		[trigger_version],
		[is_disabled],
		[for_insert],
		[for_update],
		[for_delete]
	FROM 
		[#dynamic_triggers];
	
	OPEN [cursorName];
	FETCH NEXT FROM [cursorName] INTO @triggerName, @tableName, @triggerVersion, @disabled, @insert, @update, @delete;
	
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

		SET @sql = @directive + @body;

		SELECT @currentCustomTriggerLogic = [definition] FROM dda.[extract_custom_trigger_logic](@triggerName);
		IF NULLIF(@currentCustomTriggerLogic, N'') IS NOT NULL BEGIN 

			SET @currentCustomTriggerLogic = @custTriggerMarkerStart + @currentCustomTriggerLogic + @custTriggerMarkerEnd;
			SET @sql = REPLACE(@sql, @customLogicPlaceHolder, @currentCustomTriggerLogic);

			IF @PrintOnly = 1 BEGIN 
				PRINT N'Custom Logic Found in Trigger ' + @triggerName + N'. Logic would be forwarded into updated trigger definiton.';
				PRINT N'		---->' + @currentCustomTriggerLogic + N'<----';
			END;
		END;

		IF @PrintOnly = 1 BEGIN
			PRINT N'-- IF @PrintONly were set to 0, the following change would have been executed: ';
			PRINT @directive + N' AS ..... <updated_trigger_body_here>...';
			PRINT N''
		  END; 
		ELSE BEGIN 
		
			BEGIN TRY
				BEGIN TRAN;

					EXEC sp_executesql 
						@sql;

					IF (@triggerVersion <> @latestVersion) OR (@ForceUpdates = 1) BEGIN 
						
						SELECT 
							@triggerSchemaName = PARSENAME(@tableName, 2), 
							@triggerTableName = PARSENAME(@tableName, 1), 
							@triggerNameOnly = PARSENAME(@triggerName, 1);

						-- update version in meta-data/extended properties: 
						EXEC sys.[sp_updateextendedproperty]
							@name = N'DDATrigger',
							@value = @latestVersion,
							@level0type = 'SCHEMA',
							@level0name = @triggerSchemaName,
							@level1type = 'TABLE',
							@level1name = @triggerTableName,
							@level2type = 'TRIGGER',
							@level2name = @triggerNameOnly;

						PRINT N'Updated ' + @triggerName + N' on ' + @tableName + N' from version ' + @triggerVersion + N' to version ' + @latestVersion + N'.';
					  END;
					ELSE BEGIN 
						--PRINT N'Updated ' + @triggerName + N' on ' + @tableName + N'....';
						PRINT N'Updated ' + @triggerName + N' on ' + @tableName + N' to version ' + @latestVersion + N'.';
					END;
				
				COMMIT;

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
	
		FETCH NEXT FROM [cursorName] INTO @triggerName, @tableName, @triggerVersion, @disabled, @insert, @update, @delete;
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
/*


*/

IF OBJECT_ID('dda.disable_dynamic_triggers','P') IS NOT NULL
	DROP PROC dda.[disable_dynamic_triggers];
GO

CREATE PROC dda.[disable_dynamic_triggers]
	@TargetTriggers				nvarchar(MAX)				= N'{ALL}', 
	@ExcludedTriggers			nvarchar(MAX)				= NULL, 
	@PrintOnly					bit							= 1
AS
    SET NOCOUNT ON; 

	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	SET @TargetTriggers = ISNULL(NULLIF(@TargetTriggers, N''), N'{ALL}');
	SET @ExcludedTriggers = NULLIF(@ExcludedTriggers, N'');
	SET @PrintOnly = ISNULL(@PrintOnly, 1);

	IF @ExcludedTriggers IS NOT NULL AND @TargetTriggers <> N'{ALL}' BEGIN 
		RAISERROR(N'@ExcludedTriggers can ONLY be set when @TargetTriggers is set to the value ''{ALL}'' - i.e., either specify specific triggers for 
			@TargetTriggers by name, or specify ''{ALL}'' + the names of any excluded triggers via @ExcludedTriggers.', 16, 1);
		RETURN -1;
	END;

	CREATE TABLE #dynamic_triggers (
		[parent_table] nvarchar(260) NULL,
		[trigger_name] nvarchar(260) NULL,
		[trigger_version] sysname NULL,
		[custom_trigger_logic] nvarchar(MAX) NULL,
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
		[trigger_version],
		[custom_trigger_logic],
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

	IF @TargetTriggers <> N'{ALL}' BEGIN 
		
		DELETE FROM [#dynamic_triggers] 
		WHERE 
			PARSENAME([trigger_name], 1) NOT IN (
				SELECT 
					PARSENAME([result], 1)
				FROM 
					dda.[split_string](@TargetTriggers, N',', 1)
			);
	END;
	
	IF @ExcludedTriggers IS NOT NULL BEGIN 
		
		DELETE FROM [#dynamic_triggers] 
		WHERE 
			PARSENAME([trigger_name], 1) IN (
				SELECT 
					PARSENAME([result], 1)
				FROM 
					dda.[split_string](@ExcludedTriggers, N',', 1)

			)
	END;

	IF NOT EXISTS (SELECT NULL FROM [#dynamic_triggers]) BEGIN 
		RAISERROR(N'No triggers specified for modification. Either the explicitly named triggers in @TargetTriggers were not matched or, if @TargetTriggers was set to ''{ALL}'', @ExcludedTriggers have removed all potential targets.', 16, 1);
		RETURN -3;
	END;

	IF @PrintOnly = 1 BEGIN 
		PRINT N'-- NOTE: The following commands WOULD be execute if @PrintOnly were set to 0. ';
		PRINT N'--		By DEFAULT, @PrintOnly is set to 1 - to SHOW what changes would be made - without executing them. ';
		PRINT N' ';
	END;

	DECLARE @triggerName sysname, @tableName sysname, @is_disabled bit; 
	DECLARE @sql nvarchar(MAX);

	DECLARE [walker] CURSOR LOCAL FAST_FORWARD FOR 
	SELECT 
		trigger_name, 
		[parent_table],
		[is_disabled]
	FROM 
		[#dynamic_triggers];
	
	OPEN [walker];
	FETCH NEXT FROM [walker] INTO @triggerName, @tableName, @is_disabled;
	
	WHILE @@FETCH_STATUS = 0 BEGIN
	
		IF @is_disabled = 0 BEGIN 
			SET @sql = N'ALTER TABLE ' + @tableName + N' DISABLE TRIGGER ' + PARSENAME(@triggerName, 1) + N';';
			
			IF @PrintOnly = 1 BEGIN 
				PRINT @sql;
			  END;
			ELSE BEGIN 
				EXEC sp_executesql @sql;
			END;
		  END;
		ELSE BEGIN 
			IF @PrintOnly = 1 
				PRINT N'-- Trigger ' + @triggerName + N' is ALREADY disabled. No changes will be made.';
			ELSE 
				PRINT N'-- Trigger' + @triggerName + N' was ALREADY disabled. No changes were made.';
		END;
	
		FETCH NEXT FROM [walker] INTO @triggerName, @tableName, @is_disabled;
	END;
	
	CLOSE [walker];
	DEALLOCATE [walker];

	RETURN 0;
GO


-----------------------------------
/*


*/

IF OBJECT_ID('dda.enable_dynamic_triggers','P') IS NOT NULL
	DROP PROC dda.[enable_dynamic_triggers];
GO

CREATE PROC dda.[enable_dynamic_triggers]
	@TargetTriggers				nvarchar(MAX)				= N'{ALL}', 
	@ExcludedTriggers			nvarchar(MAX)				= NULL, 
	@PrintOnly					bit							= 1
AS
    SET NOCOUNT ON; 

	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	SET @TargetTriggers = ISNULL(NULLIF(@TargetTriggers, N''), N'{ALL}');
	SET @ExcludedTriggers = NULLIF(@ExcludedTriggers, N'');
	SET @PrintOnly = ISNULL(@PrintOnly, 1);

	IF @ExcludedTriggers IS NOT NULL AND @TargetTriggers <> N'{ALL}' BEGIN 
		RAISERROR(N'@ExcludedTriggers can ONLY be set when @TargetTriggers is set to the value ''{ALL}'' - i.e., either specify specific triggers for 
			@TargetTriggers by name, or specify ''{ALL}'' + the names of any excluded triggers via @ExcludedTriggers.', 16, 1);
		RETURN -1;
	END;

	CREATE TABLE #dynamic_triggers (
		[parent_table] nvarchar(260) NULL,
		[trigger_name] nvarchar(260) NULL,
		[trigger_version] sysname NULL,
		[custom_trigger_logic] nvarchar(MAX) NULL,
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
		[trigger_version],
		[custom_trigger_logic],
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

	IF @TargetTriggers <> N'{ALL}' BEGIN 
		
		DELETE FROM [#dynamic_triggers] 
		WHERE 
			PARSENAME([trigger_name], 1) NOT IN (
				SELECT 
					PARSENAME([result], 1)
				FROM 
					dda.[split_string](@TargetTriggers, N',', 1)
			);
	END;
	
	IF @ExcludedTriggers IS NOT NULL BEGIN 
		
		DELETE FROM [#dynamic_triggers] 
		WHERE 
			PARSENAME([trigger_name], 1) IN (
				SELECT 
					PARSENAME([result], 1)
				FROM 
					dda.[split_string](@ExcludedTriggers, N',', 1)

			)
	END;

	IF NOT EXISTS (SELECT NULL FROM [#dynamic_triggers]) BEGIN 
		RAISERROR(N'No triggers specified for modification. Either the explicitly named triggers in @TargetTriggers were not matched or, if @TargetTriggers was set to ''{ALL}'', @ExcludedTriggers have removed all potential targets.', 16, 1);
		RETURN -3;
	END;

	IF @PrintOnly = 1 BEGIN 
		PRINT N'-- NOTE: ';
		PRINT N'--		NO COMMANDS or CHANGES have been EXECUTED.';
		PRINT N'--			By DEFAULT, @PrintOnly is set to 1 - meaning that execution will only show what WOULD be changed if @PrintOnly were set to 0.';
		PRINT N'';
		PRINT N'';
	END;

	DECLARE @triggerName sysname, @tableName sysname, @is_disabled bit; 
	DECLARE @sql nvarchar(MAX);

	DECLARE [walker] CURSOR LOCAL FAST_FORWARD FOR 
	SELECT 
		trigger_name, 
		[parent_table],
		[is_disabled]
	FROM 
		[#dynamic_triggers];
	
	OPEN [walker];
	FETCH NEXT FROM [walker] INTO @triggerName, @tableName, @is_disabled;
	
	WHILE @@FETCH_STATUS = 0 BEGIN
	
		IF @is_disabled = 1 BEGIN 
			SET @sql = N'ALTER TABLE ' + @tableName + N' ENABLE TRIGGER ' + PARSENAME(@triggerName, 1) + N';';
			
			IF @PrintOnly = 1 BEGIN 
				PRINT @sql;
			  END;
			ELSE BEGIN 
				EXEC sp_executesql @sql;
			END;
		  END;
		ELSE BEGIN 
			IF @PrintOnly = 0 
				PRINT N'-- Trigger ' + @triggerName + N' is ALREADY enabled. No changes will be made.';
			ELSE 
				PRINT N'-- Trigger' + @triggerName + N' was ALREADY enabled. No changes were made.';
		END;
	
		FETCH NEXT FROM [walker] INTO @triggerName, @tableName, @is_disabled;
	END;
	
	CLOSE [walker];
	DEALLOCATE [walker];

	IF @PrintOnly = 1 BEGIN 
		PRINT N'';
		PRINT N'';
		PRINT N'-- NOTE: '
		PRINT N'--		@PrintOnly is set to 1 - no changes were made.';
	END;

	RETURN 0;
GO


-----------------------------------


IF OBJECT_ID('dda.remove_obsolete_audit_data','P') IS NOT NULL
	DROP PROC [dda].[remove_obsolete_audit_data];
GO

CREATE PROC [dda].[remove_obsolete_audit_data]
	@DaysWorthOfDataToKeep					int,
	@BatchSize								int			= 2000,
	@WaitForDelay							sysname		= N'00:00:01.500',
	@AllowDynamicBatchSizing				bit			= 1,
	@MaxAllowedBatchSizeMultiplier			int			= 5, 
	@TargetBatchMilliseconds				int			= 2800,
	@MaxExecutionSeconds					int			= NULL,
	@MaxAllowedErrors						int			= 1,
	@TreatDeadlocksAsErrors					bit			= 0,
	@StopIfTempTableExists					sysname		= NULL
AS
    SET NOCOUNT ON; 

	-- NOTE: this code was generated from admindb.dbo.blueprint_for_batched_operation.
	
	-- Parameter Scrubbing/Cleanup:
	SET @WaitForDelay = NULLIF(@WaitForDelay, N'');
	SET @StopIfTempTableExists = ISNULL(@StopIfTempTableExists, N'');
	
	---------------------------------------------------------------------------------------------------------------
	-- Initialization:
	---------------------------------------------------------------------------------------------------------------
	SET NOCOUNT ON; 

	CREATE TABLE [#batched_operation_602436EA] (
		[detail_id] int IDENTITY(1,1) NOT NULL, 
		[timestamp] datetime NOT NULL DEFAULT GETDATE(), 
		[is_error] bit NOT NULL DEFAULT (0), 
		[detail] nvarchar(MAX) NOT NULL
	); 

	-- Processing (variables/etc.)
	DECLARE @dumpHistory bit = 0;
	DECLARE @currentRowsProcessed int = @BatchSize; 
	DECLARE @totalRowsProcessed int = 0;
	DECLARE @errorDetails nvarchar(MAX);
	DECLARE @errorsOccured bit = 0;
	DECLARE @currentErrorCount int = 0;
	DECLARE @deadlockOccurred bit = 0;
	DECLARE @startTime datetime = GETDATE();
	DECLARE @batchStart datetime;
	DECLARE @milliseconds int;
	DECLARE @initialBatchSize int = @BatchSize;
	DECLARE @continue bit = 1;
	
	---------------------------------------------------------------------------------------------------------------
	-- Processing:
	---------------------------------------------------------------------------------------------------------------
	WHILE @continue = 1 BEGIN 
	
		SET @batchStart = GETDATE();
	
		BEGIN TRY
			BEGIN TRAN; 
				
				-------------------------------------------------------------------------------------------------
				-- batched operation code:
				-------------------------------------------------------------------------------------------------
				DELETE [t]
				FROM dda.[audits] t WITH(ROWLOCK)
				INNER JOIN (
					SELECT TOP (@BatchSize) 
						[audit_id]  
					FROM 
						dda.[audits] WITH(NOLOCK)  
					WHERE 
						[timestamp] < DATEADD(DAY, 0 - @DaysWorthOfDataToKeep, @startTime) 
					) x ON t.[audit_id]= x.[audit_id]; 

				-------------------------------------------
				SELECT 
					@currentRowsProcessed = @@ROWCOUNT, 
					@totalRowsProcessed = @totalRowsProcessed + @@ROWCOUNT;

			COMMIT; 

			IF @currentRowsProcessed <> @BatchSize SET @continue = 0;

			INSERT INTO [#batched_operation_602436EA] (
				[timestamp],
				[detail]
			)
			SELECT 
				GETDATE() [timestamp], 
				(
					SELECT 
						@BatchSize [settings.batch_size], 
						@WaitForDelay [settings.wait_for], 
						@currentRowsProcessed [progress.current_batch_count], 
						@totalRowsProcessed [progress.total_rows_processed],
						DATEDIFF(MILLISECOND, @batchStart, GETDATE()) [progress.batch_milliseconds], 
						DATEDIFF(MILLISECOND, @startTime, GETDATE())[progress.total_milliseconds]
					FOR JSON PATH, ROOT('detail')
				) [detail];

			IF @MaxExecutionSeconds > 0 AND (DATEDIFF(SECOND, @startTime, GETDATE()) >= @MaxExecutionSeconds) BEGIN 
				INSERT INTO [#batched_operation_602436EA] (
					[timestamp],
					[is_error],
					[detail]
				)
				SELECT
					GETDATE() [timestamp], 
					1 [is_error], 
					( 
						SELECT 
							@currentRowsProcessed [progress.current_batch_count], 
							@totalRowsProcessed [progress.total_rows_processed],
							DATEDIFF(MILLISECOND, @batchStart, GETDATE()) [progress.batch_milliseconds], 
							DATEDIFF(MILLISECOND, @startTime, GETDATE())[progress.total_milliseconds],
							CONCAT(N'Maximum execution seconds allowed for execution met/exceeded. Max Allowed Seconds: ', @MaxExecutionSeconds, N'.') [errors.error]
						FOR JSON PATH, ROOT('detail')
					) [detail];
			
				SET @errorsOccured = 1;

				GOTO Finalize;		
			END;

			IF OBJECT_ID(N'tempdb..' + @StopIfTempTableExists) IS NOT NULL BEGIN 
				INSERT INTO [#batched_operation_602436EA] (
					[timestamp],
					[is_error],
					[detail]
				)
				SELECT
					GETDATE() [timestamp], 
					1 [is_error], 
					( 
						SELECT 
							@currentRowsProcessed [progress.current_batch_count], 
							@totalRowsProcessed [progress.total_rows_processed],
							DATEDIFF(MILLISECOND, @batchStart, GETDATE()) [progress.batch_milliseconds], 
							DATEDIFF(MILLISECOND, @startTime, GETDATE())[progress.total_milliseconds],
							N'Graceful execution shutdown/bypass directive detected - object [' + @StopIfTempTableExists + N'] found in tempdb. Terminating Execution.' [errors.error]
						FOR JSON PATH, ROOT('detail')
					) [detail];
			
				SET @errorsOccured = 1;

				GOTO Finalize;
			END;

			-- Dynamic Tuning:
			SET @milliseconds = DATEDIFF(MILLISECOND, @batchStart, GETDATE());
			IF @milliseconds <= @TargetBatchMilliseconds BEGIN 
				IF @BatchSize < (@initialBatchSize * @MaxAllowedBatchSizeMultiplier) BEGIN

					SET @BatchSize = FLOOR((@BatchSize + (@BatchSize * .2)) / 100) * 100; 
					IF @BatchSize > (@initialBatchSize * @MaxAllowedBatchSizeMultiplier) 
						SET @BatchSize = (@initialBatchSize * @MaxAllowedBatchSizeMultiplier);
				END;
			  END;
			ELSE BEGIN 
				IF @BatchSize > (@initialBatchSize / @MaxAllowedBatchSizeMultiplier) BEGIN

					SET @BatchSize = FLOOR((@BatchSize - (@BatchSize * .2)) / 100) * 100;
					IF @BatchSize < (@initialBatchSize / @MaxAllowedBatchSizeMultiplier)
						SET @BatchSize = (@initialBatchSize / @MaxAllowedBatchSizeMultiplier);
				END;
			END; 
		
			WAITFOR DELAY @WaitForDelay;
		END TRY
		BEGIN CATCH 
			
			IF ERROR_NUMBER() = 1205 BEGIN
		
				INSERT INTO [#batched_operation_602436EA] (
					[timestamp],
					[is_error],
					[detail]
				)
				SELECT
					GETDATE() [timestamp], 
					1 [is_error], 
					( 
						SELECT 
							@currentRowsProcessed [progress.current_batch_count], 
							@totalRowsProcessed [progress.total_rows_processed],
							N'Deadlock Detected. Logging to history table - but not counting deadlock as normal error for purposes of error handling/termination.' [errors.error]
						FOR JSON PATH, ROOT('detail')
					) [detail];
					   
				SET @deadlockOccurred = 1;		
			END; 

			SELECT @errorDetails = N'Error Number: ' + CAST(ERROR_NUMBER() AS sysname) + N'. Message: ' + ERROR_MESSAGE();

			IF @@TRANCOUNT > 0
				ROLLBACK; 

			INSERT INTO [#batched_operation_602436EA] (
				[timestamp],
				[is_error],
				[detail]
			)
			SELECT
				GETDATE() [timestamp], 
				1 [is_error], 
				( 
					SELECT 
						@currentRowsProcessed [progress.current_batch_count], 
						@totalRowsProcessed [progress.total_rows_processed],
						N'Unexpected Error Occurred: ' + @errorDetails [errors.error]
					FOR JSON PATH, ROOT('detail')
				) [detail];
					   
			SET @errorsOccured = 1;
		
			SET @currentErrorCount = @currentErrorCount + 1; 
			IF @currentErrorCount >= @MaxAllowedErrors BEGIN 
				INSERT INTO [#batched_operation_602436EA] (
					[timestamp],
					[is_error],
					[detail]
				)
				SELECT
					GETDATE() [timestamp], 
					1 [is_error], 
					( 
						SELECT 
							@currentRowsProcessed [progress.current_batch_count], 
							@totalRowsProcessed [progress.total_rows_processed],
							CONCAT(N'Max allowed errors count reached/exceeded: ', @MaxAllowedErrors, N'. Terminating Execution.') [errors.error]
						FOR JSON PATH, ROOT('detail')
					) [detail];

				GOTO Finalize;
			END;
		END CATCH;
	END;

	---------------------------------------------------------------------------------------------------------------
	-- Finalization/Reporting:
	---------------------------------------------------------------------------------------------------------------

Finalize:

	IF @deadlockOccurred = 1 BEGIN 
		PRINT N'NOTE: One or more deadlocks occurred.'; 
		SET @dumpHistory = 1;
	END;

	IF @errorsOccured = 1 BEGIN 
		SET @dumpHistory = 1;
	END;

	IF @dumpHistory = 1 BEGIN 

		SELECT * FROM [#batched_operation_602436EA] ORDER BY [is_error], [detail_id];

		RAISERROR(N'Errors occurred during cleanup.', 16, 1);

	END;

	RETURN 0;
GO


-----------------------------------
/*


*/

IF OBJECT_ID('dda.set_bypass_triggers_on','P') IS NOT NULL
	DROP PROC dda.[set_bypass_triggers_on];
GO

CREATE PROC dda.[set_bypass_triggers_on]

AS
    SET NOCOUNT ON; 

	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 
	
	/* Disallow Explicit User Transactions - i.e., triggers have to be 'turned on/off' outside of a user-enlisted TX: */
	IF @@TRANCOUNT > 0 BEGIN 
		RAISERROR(15002, 16, 1,'dda.bypass_dynamic_triggers');
		RETURN -1;
	END;

	/* If not a member of db_owner, can not execute... */
	IF NOT IS_ROLEMEMBER('db_owner') = 1 BEGIN
		RAISERROR('Procedure dda.bypass_dynamic_triggers may only be called by members of the db_owner role (including members of SysAdmin server-role).', 16, 1);
		RETURN -10;
	END;

	/* Load Current Trigger: */
	DECLARE @definitionID int; 
	DECLARE @definition nvarchar(MAX); 
	
	SELECT @definitionID = [object_id] FROM sys.[triggers] WHERE [name] = N'dynamic_data_auditing_trigger_template' AND [parent_id] = OBJECT_ID('dda.trigger_host');
	IF @definitionID IS NULL BEGIN 
		/* Guessing the chances of this are UNLIKELY (i.e., can't see, say, this SPROC existing but the trigger being gone?), but...still, need to account for this. */
		RAISERROR(N'Dynamic Data Auditing Trigger Template NOT found against table dda.trigger_host. Please re-deploy core DDA plumbing before continuing.', 16, -1);
		RETURN -32; 
	END;	

	SELECT @definition = [definition] FROM sys.[sql_modules] WHERE [object_id] = @definitionID;
	DECLARE @pattern nvarchar(MAX) = N'%IF @context = 0x% BEGIN%';

	/* Extract Context ... (via ugly brute-force approach) ... */
	DECLARE @contextStart int = PATINDEX(@pattern, @definition);
	DECLARE @contextBody nvarchar(MAX) = SUBSTRING(@definition, @contextStart, LEN(@pattern) + 128);
	DECLARE @contextString sysname, @context varbinary(128);

	SET @contextStart = PATINDEX(N'% 0x%', @contextBody);
	SET @contextBody = LTRIM(SUBSTRING(@contextBody, @contextStart, LEN(@contextBody) - @contextStart));
	SET @contextStart = PATINDEX(N'% %', @contextBody);
	SET @contextString = RTRIM(LEFT(@contextBody, @contextStart));
	SET @context = CONVERT(varbinary(128), @contextString, 1);

	/* SET context_info() to bypass value: */
	SET CONTEXT_INFO @context;

	PRINT N'CONTEXT_INFO has been set to value of ' + @contextString + N' - Dynamic Data Audit Triggers will now be bypassed until CONTEXT_INFO is set to another value or the current session is terminated.';

	RETURN 0;
GO


-----------------------------------
/*


*/

IF OBJECT_ID('dda.set_bypass_triggers_off','P') IS NOT NULL
	DROP PROC dda.[set_bypass_triggers_off];
GO

CREATE PROC dda.[set_bypass_triggers_off]

AS
    SET NOCOUNT ON; 

	-- [v5.6.4865.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 
	
	/* Disallow Explicit User Transactions - i.e., triggers have to be 'turned on/off' outside of a user-enlisted TX: */
	IF @@TRANCOUNT > 0 BEGIN 
		RAISERROR(15002, 16, 1,'dda.bypass_dynamic_triggers');
		RETURN -1;
	END;

	/* If not a member of db_owner, can not execute... */
	IF NOT IS_ROLEMEMBER('db_owner') = 1 BEGIN
		RAISERROR('Procedure dda.bypass_dynamic_triggers may only be called by members of the db_owner role (including members of SysAdmin server-role).', 16, 1);
		RETURN -10;
	END;
	
	SET CONTEXT_INFO 0x0;

	RETURN 0;
GO


----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 5. Update version_history with details about current version (i.e., if we got this far, the deployment is successful). 
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DECLARE @CurrentVersion varchar(20) = N'5.6.4865.1';
DECLARE @VersionDescription nvarchar(200) = N'Testing Build and Deployment';
DECLARE @InstallType nvarchar(20) = N'Install. ';

IF EXISTS (SELECT NULL FROM dda.[version_history])
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

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 6. Notify of need to run dda.update_trigger_definitions if/as needed:
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT NULL FROM sys.[triggers] t INNER JOIN sys.[extended_properties] p ON t.[object_id] = p.[major_id] WHERE p.[name] = N'DDATrigger' AND p.[value] = 'true' AND OBJECT_NAME(t.[object_id]) <> N'dynamic_data_auditing_trigger_template') BEGIN 
	SELECT N'Deployed DDA Triggers Detected' [scan_outcome], N'Please execute dda.update_trigger_definitions.' [recommendation], N'NOTE: Set @PrintOnly = 0 on dda.update_trigger_definitions to MAKE changes. By default, it only shows WHICH changes it WOULD make.' [notes];

END;
