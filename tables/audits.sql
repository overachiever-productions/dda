/*


		4. and ... then I'll need to change dda.get_audit_data to include a new/optional column for ... e_user 
			and, might also just? want an option (PREMIUM) where ... we can see JUST rows executed by impersonated logins/users? 
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
					N'<legacy>' AS [executing_user],
					[operation],
					[transaction_id],
					[row_count],
					[audit] 
				FROM 
					dda.[audits];

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