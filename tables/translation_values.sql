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