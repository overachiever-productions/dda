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