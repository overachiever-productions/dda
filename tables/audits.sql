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