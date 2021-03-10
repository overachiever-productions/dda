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