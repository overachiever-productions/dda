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


USE [your_db_here];
GO

IF DB_NAME() <> 'your_db_here' BEGIN
	-- Throw an error and TERMINATE the connection (to avoid execution in the WRONG database (master, etc.)
	RAISERROR('Please make sure you''re in your target database - i.e., change directives in Section 0 of this script.', 21, 1) WITH LOG;
END;


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
		[translation_value_type] int NOT NULL CONSTRAINT DF_translation_values_translation_value_type DEFAULT (1), -- default to string
		[notes] nvarchar(MAX) NULL,
		CONSTRAINT PK_translation_keys PRIMARY KEY NONCLUSTERED ([translation_key_id])
	);

	CREATE UNIQUE CLUSTERED INDEX CLIX_translation_values_by_identifiers ON dda.[translation_values] ([table_name], [column_name], [key_value]);

END;

-- v0.9 to v1.0 Upgrade: 
IF NOT EXISTS (SELECT NULL FROM sys.columns	WHERE [object_id] = OBJECT_ID('dda.translation_values') AND [name] = N'translation_value_type') BEGIN 

	CREATE TABLE dda.translation_values2 (
		[translation_key_id] int IDENTITY(1,1) NOT NULL, 
		[table_name] sysname NOT NULL, 
		[column_name] sysname NOT NULL, 
		[key_value] sysname NOT NULL, 
		[translation_value] sysname NOT NULL,
		[translation_value_type] int NOT NULL CONSTRAINT DF_translation_values_translation_value_type DEFAULT (1), -- default to string
		[notes] nvarchar(MAX) NULL,
		CONSTRAINT PK_translation_keys2 PRIMARY KEY NONCLUSTERED ([translation_key_id])
	);

	CREATE UNIQUE CLUSTERED INDEX CLIX_translation_values2_by_identifiers ON dda.[translation_values2] ([table_name], [column_name], [key_value]);

	BEGIN TRY
		BEGIN TRAN; 
		
			SET IDENTITY_INSERT dda.[translation_values2] ON;

			INSERT INTO [dda].[translation_values2] (
				[translation_key_id],
				[table_name],
				[column_name],
				[key_value],
				[translation_value],
				[translation_value_type],
				[notes]
			)
			SELECT 
				[translation_key_id],
				[table_name],
				[column_name],
				[key_value],
				[translation_value],
				1 [translation_value_type], -- default to 1 (string)
				[notes] 
			FROM 
				dda.[translation_values];

			SET IDENTITY_INSERT dda.[translation_values2] OFF;

			DROP TABLE dda.[translation_values]; 

			EXEC sp_rename N'dda.translation_values2.CLIX_translation_values2_by_identifiers', N'CLIX_translation_values_by_identifiers', N'INDEX';

			EXEC sp_rename N'dda.translation_values2', N'translation_values'; -- table will STAY in the dda schema
			EXEC sp_rename N'dda.PK_translation_keys2', N'PK_translation_keys';

		COMMIT;
	END TRY
	BEGIN CATCH
		SELECT N'WARNING!!!!!' [Deployment Error], N'Failured attempt to add translation_value_type to dda.translation_values' [Context], ERROR_NUMBER() [Error_Number], ERROR_MESSAGE() [Error_Message];
		ROLLBACK;
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

IF EXISTS (SELECT NULL FROM sys.columns WHERE [object_id] = OBJECT_ID('dda.audits') AND [name] = N'operation' AND [max_length] = 9) BEGIN 
	ALTER TABLE dda.[audits] ALTER COLUMN [operation] char(6) NOT NULL;
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

	'Stolen' from S4. 

*/

IF OBJECT_ID('dda.get_engine_version','FN') IS NOT NULL
	DROP FUNCTION dda.get_engine_version;
GO

CREATE FUNCTION dda.get_engine_version() 
RETURNS decimal(4,2)
AS
	-- [v2.0.3535.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

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
	-- [v2.0.3535.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

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
	-- [v2.0.3535.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

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

	-- [v2.0.3535.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 
	
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



------------------------------------------------------------------------------------------------------------------------------------------------------
-- DDA Trigger 
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
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

	-- [v2.0.3535.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

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
				@TargetUsers = N'sa, bilbo',
				@TargetTables = N'SortTable,Errors',
				@TransformOutput = 1,
				@FromIndex = 20,
				@ToIndex = 40;

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

	-- [v2.0.3535.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

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
		[operation_type] char(6) NOT NULL,
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
						ORDER BY 
							[k].[json_row_id], [k].[current_kvp], [k].[sort_id]
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
						ORDER BY 
							[d].[json_row_id], [d].[current_kvp], [d].[sort_id]
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
						ORDER BY 
							[c].[json_row_id]
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
					ORDER BY 
						[x2].[json_row_id], [x2].[current_kvp], [x2].[sort_id]
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
					ORDER BY 
						[x2].[json_row_id], [x2].[current_kvp], [x2].[sort_id]
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


DECLARE @get_audit_data nvarchar(MAX) = N'
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

	-- [v2.0.3535.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	SET @TargetUsers = NULLIF(@TargetUsers, N'''');
	SET @TargetTables = NULLIF(@TargetTables, N'''');		
	SET @TransformOutput = ISNULL(@TransformOutput, 1);

	SET @FromIndex = ISNULL(@FromIndex, 1);
	SET @ToIndex = ISNULL(@ToIndex, 1);

	IF @StartTime IS NOT NULL AND @EndTime IS NULL BEGIN 
		SET @EndTime = DATEADD(MINUTE, 2, GETDATE());
	END;

	IF @EndTime IS NOT NULL AND @StartTime IS NULL BEGIN 
		RAISERROR(N''@StartTime MUST be specified if @EndTime is specified. (@StartTime can be specified without @EndTime - and @EndTime will be set to GETDATE().)'', 16, 1);
		RETURN - 10;
	END;

	IF @StartTime IS NULL AND @EndTime IS NULL BEGIN
		IF @TargetUsers IS NULL AND @TargetTables IS NULL BEGIN 
			RAISERROR(N''Queries against Audit data MUST be constrained - either specify @StartTime [+ @EndTIme], or @TargetUsers, or @TargetTables - or a combination of constraints.'', 16, 1);
			RETURN -11;
		END;
	END;

	IF @StartTime IS NOT NULL BEGIN 
		IF @StartTime > @EndTime BEGIN
			RAISERROR(''@StartTime may not be > @EndTime - please check inputs and try again.'', 16, 1);
			RETURN -12;
		END;
	END;

	-- Grab matching rows based upon inputs/constraints:
	DECLARE @coreQuery nvarchar(MAX) = N''WITH total AS (
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
'';

	DECLARE @timeFilters nvarchar(MAX) = N'''';
	DECLARE @users nvarchar(MAX) = N'''';
	DECLARE @tables nvarchar(MAX) = N'''';
	DECLARE @predicated bit = 0;

	IF @StartTime IS NOT NULL BEGIN 
		SET @timeFilters = N''[timestamp] >= '''''' + CONVERT(sysname, @StartTime, 121) + N'''''' AND [timestamp] <= '''''' + CONVERT(sysname, @EndTime, 121) + N'''''' ''; 
		SET @predicated = 1;
	END;

	IF @TargetUsers IS NOT NULL BEGIN 
		IF @TargetUsers LIKE N''%,%'' BEGIN 
			SET @users  = N''[user] IN ('';

			SELECT 
				@users = @users + N'''''''' + [result] + N'''''', ''
			FROM 
				dda.[split_string](@TargetUsers, N'','', 1)
			ORDER BY 
				[row_id];

			SET @users = LEFT(@users, LEN(@users) - 1) + N'') '';

		  END;
		ELSE BEGIN 
			SET @users = N''[user] = '''''' + @TargetUsers + N'''''' '';
		END;
		
		IF @predicated = 1 SET @users = N''AND '' + @users;
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
		
		IF @predicated = 1 SET @tables = N''AND '' + @tables;
	END;

	SET @coreQuery = REPLACE(@coreQuery, N''{TimeFilters}'', @timeFilters);
	SET @coreQuery = REPLACE(@coreQuery, N''{Users}'', @users);
	SET @coreQuery = REPLACE(@coreQuery, N''{Tables}'', @tables);
	
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
		[user] sysname NOT NULL,
		[operation_type] char(6) NOT NULL,
		[transaction_id] int NOT NULL,
		[row_count] int NOT NULL,
		[change_details] nvarchar(max) NULL, 
		[translated_change_key] nvarchar(MAX) NULL, 
		[translated_change_detail] nvarchar(MAX) NULL, 
		[translated_multi_row] nvarchar(MAX) NULL
	);

	-- NOTE: INSERT + EXEC (dynamic-SQL with everything needed from dda.audits in a single ''gulp'') would make more sense here. 
	--		BUT, INSERT + EXEC causes dreaded "INSERT EXEC can''t be nested..." error if/when UNIT tests are used to test this code. 
	--			So, this ''hack'' of grabbing JSON (dynamically), shredding it, and JOINing ''back'' to dda.audits... exists below):
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
		[a].[schema] + N''.'' + [a].[table] [table],
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
		[json_row_id] int NOT NULL DEFAULT 0,  -- for ''multi-row'' ... rows. 
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
		N''key'' [kvp_type],
		[x].[table], 
		[x].[row_number],
		[y].[Key] [column], 
		[y].[Value] [value],
		[y].[Type] [value_type]
	FROM 
		[#raw_data] x
		OUTER APPLY OPENJSON(JSON_QUERY(x.[change_details], ''$[0].key''), ''$'') z
		CROSS APPLY OPENJSON(z.[Value], N''$'') y
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
		N''detail'' [kvp_type],
		[x].[table], 
		[x].[row_number],
		[y].[Key] [column], 
		[y].[Value] [value],
		[y].[Type] [value_type]
	FROM 
		[#raw_data] x 
		OUTER APPLY OPENJSON(JSON_QUERY(x.[change_details], ''$[0].detail''), ''$'') z
		CROSS APPLY OPENJSON(z.[Value], N''$'') y
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
				CROSS APPLY OPENJSON(JSON_QUERY([x].[change_details], N''$'')) r
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
			N''key'' [kvp_type], 
			[x].[table], 
			[x].[row_number],
			[x].[json_row_id], 
			[y].[Key] [column], 
			[y].[Value] [value],
			[y].[Type] [value_type]
		FROM 
			[row_keys] x
			OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], ''$.key''), ''$'') z
			CROSS APPLY OPENJSON(z.[Value], N''$'') y;

		-- ditto, for details:
		WITH [row_details] AS ( 
			SELECT 
				[x].[table], 
				[x].[row_number],
				[r].[Key] [json_row_id], 
				[r].[Value] [change_details]
			FROM 
				[#raw_data] x 
				CROSS APPLY OPENJSON(JSON_QUERY([x].[change_details], N''$'')) r
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
			N''detail'' [kvp_type], 
			[x].[table], 
			[x].[row_number],
			[x].[json_row_id], 
			[y].[Key] [column], 
			[y].[Value] [value],
			[y].[Type] [value_type]
		FROM 
			[row_details] x
			OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], ''$.detail''), ''$'') z
			CROSS APPLY OPENJSON(z.[Value], N''$'') y;
	END;

	UPDATE [#key_value_pairs] 
	SET 
		[from_value] = ISNULL(JSON_VALUE([value], N''$.from''), N''null''), 
		[to_value] = ISNULL(JSON_VALUE([value], N''$.to''), N''null'')
	WHERE 
		ISJSON([value]) = 1 AND [value] LIKE ''%from":%"to":%'';

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
			AND x.[value] NOT LIKE N''{"from":%"to":%'';

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
		[translated_update_value] = N''{"from":'' + CASE 
				WHEN [translated_from_value_type] = 1 THEN N''"'' + ISNULL([translated_from_value], [from_value]) + N''"'' 
				ELSE ISNULL([translated_from_value], [from_value])
			END + N'', "to":'' + CASE 
				WHEN [translated_to_value_type] = 1 THEN N''"'' + ISNULL([translated_to_value], [to_value]) + N''"''
				ELSE + ISNULL([translated_to_value], [to_value])
			END + N''}''
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
			[kvp_type] = N''key''
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
			[kvp_type] = N''detail''

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
		
	-- collapse multi-row results back down to a single ''set''/row of results:
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
				[flattened].[kvp_type] = N''key''

		), 
		[details] AS ( 
			SELECT 
				*
			FROM 
				[flattened]
			WHERE 
				[flattened].[kvp_type] = N''detail''
		),
		[collapsed] AS (
			SELECT 
				x.[row_number], 
				f.[json_row_id], 
				(
					SELECT
						STRING_AGG(
							N''"'' + [k].[column] + N''":'' + 
							CASE 
								WHEN [k].[value_type] = 2 THEN [k].[value]
								ELSE N''"'' + [k].[value] + N''"''
							END + 
							CASE 
								WHEN [k].[current_kvp] = [k].[kvp_count] THEN N''''
								ELSE N'',''
							END
						, '''') WITHIN GROUP (ORDER BY [k].[json_row_id], [k].[current_kvp], [k].[sort_id])
					FROM 
						[keys] [k]
					WHERE 
						[x].[row_number] = [k].[row_number] 
						AND [f].[json_row_id] = [k].[json_row_id]
				) [key_data], 
				(
					SELECT 
						STRING_AGG(
							N''"'' + [d].[column] + N''":'' + 
							CASE 
								WHEN [d].[value_type] IN (2,5) THEN [d].[value]
								ELSE N''"'' + [d].[value] + N''"''
							END + 
							CASE 
								WHEN [d].[current_kvp] = [d].[kvp_count] THEN N''''
								ELSE N'',''
							END
						, '''') WITHIN GROUP (ORDER BY [d].[json_row_id], [d].[current_kvp], [d].[sort_id])
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
				N''['' + (
					SELECT 
						STRING_AGG(N''{"key": [{'' + [c].[key_data] + N''}],"detail":[{'' + [c].[detail_data] + N''}]}'', '','') WITHIN GROUP (ORDER BY [c].[json_row_id])
						FROM [collapsed] [c] WHERE c.[row_number] = x.[row_number]
				) + N'']'' [serialized]
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
						N''"'' + [x2].[column] + N''":'' +
						CASE 
							WHEN [x2].[value_type] = 2 THEN [x2].[value] 
							ELSE N''"'' + [x2].[value] + N''"''
						END + 
						CASE 
							WHEN [x2].[current_kvp] = [x2].[kvp_count] THEN N''''
							ELSE N'',''
						END
					, '''') WITHIN GROUP (ORDER BY [x2].[json_row_id], [x2].[current_kvp], [x2].[sort_id])
				FROM 
					[#translated_kvps] x2 WHERE [x].[row_number] = [x2].[row_number] AND [x2].[kvp_type] = N''key''
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
						N''"'' + [x2].[column] + N''":'' +
						CASE 
							WHEN [x2].[value_type] IN (2, 5) THEN [x2].[value]   -- if it''s a number or json/etc... just use the RAW value
							ELSE N''"'' + [x2].[value] + N''"''
						END + 
						CASE 
							WHEN [x2].[current_kvp] = [x2].[kvp_count] THEN N''''
							ELSE N'',''
						END
					, '''') WITHIN GROUP (ORDER BY [x2].[json_row_id], [x2].[current_kvp], [x2].[sort_id])

				FROM 
					[#translated_kvps] x2 WHERE [x].[row_number] = [x2].[row_number] AND [x2].[kvp_type] = N''detail''
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
		CONCAT(DATEPART(YEAR, [timestamp]), N''-'', RIGHT(N''000'' + DATENAME(DAYOFYEAR, [timestamp]), 3), N''-'', RIGHT(N''000000000'' + CAST([transaction_id] AS sysname), 9)) [transaction_id],
		[operation_type],
		[row_count],
		CASE 
			WHEN [translated_change_key] IS NOT NULL THEN N''[{"key":[{'' + [translated_change_key] + N''}],"detail":[{'' + [translated_change_detail] + N''}]}]''
			WHEN [translated_multi_row] IS NOT NULL THEN [translated_multi_row] -- this and translated_change_key won''t ever BOTH be populated (only one OR the other).
			ELSE [change_details]
		END [change_details] 
	FROM 
		[#raw_data]
	ORDER BY 
		[row_number];

	RETURN 0;

 ';

IF (SELECT dda.get_engine_version())> 14.0  
	EXEC sp_executesql @get_audit_data;

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

	-- [v2.0.3535.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

	SELECT 'Not implemented yet.' [status];

	RETURN 0;
GO


------------------------------------------------------------------------------------------------------------------------------------------------------
-- Utilities:
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
DROP PROC IF EXISTS dda.list_dynamic_triggers; 
GO 

CREATE PROC dda.list_dynamic_triggers 

AS 
	SET NOCOUNT ON; 

	-- [v2.0.3535.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 
	
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

	-- [v2.0.3535.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

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
	@ExcludedTables				nvarchar(MAX), 
	@ExcludeTablesWithoutPKs	bigint					= 0,			-- Default behavior is to throw an error/warning - and stop. 
	@TriggerNamePattern			sysname					= N'ddat_{0}', 
	@ContinueOnError			bit						= 1,
	@PrintOnly					bit						= 0
AS
    SET NOCOUNT ON; 

	-- [v2.0.3535.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 
	
	SET @ExcludedTables = NULLIF(@ExcludedTables, N'');
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
DROP PROC IF EXISTS dda.update_trigger_definitions; 
GO 

CREATE PROC dda.update_trigger_definitions 
	@PrintOnly				bit				= 1			-- default to NON-modifying execution (i.e., require explicit change to modify).
AS 
	SET NOCOUNT ON; 

	-- [v2.0.3535.1] - License, Code, & Docs: https://github.com/overachiever-productions/dda/ 

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

		SET @sql = @directive + @body;

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


----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 5. Update version_history with details about current version (i.e., if we got this far, the deployment is successful). 
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DECLARE @CurrentVersion varchar(20) = N'2.0.3535.1';
DECLARE @VersionDescription nvarchar(200) = N'Test Build.';
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
