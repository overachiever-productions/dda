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

-- v2.0 to v3.0 Update to avoid potential for PK name collisions: 
IF EXISTS (SELECT NULL FROM sys.[indexes] WHERE [object_id] = OBJECT_ID(N'dda.audits') AND [name] = N'PK_audits' AND [is_primary_key] = 1) BEGIN
	EXEC sp_rename N'dda.audits.PK_audits', N'PK_dda_audits';
END;