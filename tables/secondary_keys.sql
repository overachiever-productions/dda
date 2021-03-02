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