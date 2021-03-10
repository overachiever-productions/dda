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