/*

	TODO: 
		current automation around deployment + updates of dynamic triggers is hard-coded/kludgey around exact
		format/specification of the "FOR INSERT, UPDATE, DELETE" text in the following trigger definition. 
			i.e., changing whitespace can/could/would-probably break 'stuff'. 

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

	-- {copyright}

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
	DECLARE @txID int = CAST(LEFT(CAST(CURRENT_TRANSACTION_ID() AS sysname), 9) AS int);

	-- Determine Operation Type: INSERT, UPDATE, or DELETE: 
	DECLARE @operationType sysname; 
	SELECT 
		@operationType = CASE 
			WHEN EXISTS(SELECT NULL FROM INSERTED) AND EXISTS(SELECT NULL FROM DELETED) THEN N'UPDATE'
			WHEN EXISTS(SELECT NULL FROM INSERTED) THEN N'INSERT'
			ELSE N'DELETE'
		END;

	IF UPPER(@operationType) IN (N'INSERT', N'UPDATE') BEGIN
		SELECT * INTO #temp_inserted FROM inserted;
		SELECT @rowCount = @@ROWCOUNT;
	END;
	
	IF UPPER(@operationType) IN (N'DELETE', N'UPDATE') BEGIN
		SELECT * INTO #temp_deleted FROM deleted;
		SELECT @rowCount = ISNULL(NULLIF(@rowCount, -1), @@ROWCOUNT);
	END;

	IF @rowCount < 1 BEGIN 
		GOTO Cleanup; -- nothing to document/audit - bail:
	END;

	DECLARE @template nvarchar(MAX) = N'SELECT @json = (SELECT 
		{AUDIT_COLUMNS} 
	FROM 
		{AUDIT_FROM} FOR JSON PATH	
);';

	DECLARE @sql nvarchar(MAX) = @template;

	DECLARE @pkColumns nvarchar(MAX) = NULL;
	EXEC dda.[extract_key_columns] 
		@TargetSchema = @schemaName,
		@TargetTable = @tableName, 
		@Output = @pkColumns OUTPUT;

	IF NULLIF(@pkColumns, N'') IS NULL BEGIN 
		-- Sadly, there is SOMEHOW not a PK defined or any surrogate mappings defined ANYMORE. (Trigger-creation scaffolding would have verified ONE or the OTHER.) 
		RAISERROR('Data Auditing Exception - No Primary Key or suitable surrogate defined against table [%s].[%s].', 16, 1, @schemaName, @tableName);
		GOTO Cleanup;
	END;

	DECLARE @key nvarchar(MAX) = N'';
	DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10); 
	DECLARE @tab nchar(1) = NCHAR(9);

	-- INSERT/DELETE: grab everything.
	IF UPPER(@operationType) IN (N'INSERT', N'DELETE') BEGIN 
		SET @sql = REPLACE(@sql, N'{AUDIT_COLUMNS}', CASE WHEN @operationType = N'INSERT' THEN N'i.*' ELSE N'd.*' END);
		SET @sql = REPLACE(@sql, N'{AUDIT_FROM}', CASE WHEN @operationType = N'INSERT' THEN N'#temp_inserted i' ELSE N'#temp_deleted d' END);
	END;
	
	-- UPDATE: use changeMap to grab modified columns only:
	IF UPPER(@operationType) = N'UPDATE' BEGIN 

		DECLARE @join nvarchar(MAX) = N'';

-- TODO: Look into detecting non-UPDATING updates i.e., SET x = y, a = b ... as the UPDATE but where x is ALREADY y, and a is ALREADY b 
--			(i.e., full or partial removal of 'duplicates'/non-changes is what we're after - i.e., if x and a were only columns in SET of UPDATE and there are no changes, 
--				maybe BAIL and don't record this? whereas if it was x OR a that had a change, just record the ONE that changed?
		DECLARE @changeMap varbinary(1024) = (SELECT COLUMNS_UPDATED());

		DECLARE @columnNames nvarchar(MAX) = N'';
		SELECT
			@columnNames = @columnNames + N'[d].' + QUOTENAME([column_name]) + N' [' + [column_name] + N'.from], ' + @crlf + @tab + @tab + N'[i].' + QUOTENAME([column_name]) + N' [' + [column_name] + N'.to], '
		FROM 
			dda.[translate_modified_columns](@auditedTable, @changeMap)
		WHERE 
			[modified] = 1 
		ORDER BY 
			[column_id]; 

		IF LEN(@columnNames) > 0 SET @columnNames = LEFT(@columnNames, LEN(@columnNames) - 1);

		DECLARE @from nvarchar(MAX) = N'#temp_deleted d ' + @crlf + @tab + @tab + N'INNER JOIN #temp_inserted i ON ';

		SELECT
			@join = @join + N'[d].' + QUOTENAME([result]) + N' = [i].' + QUOTENAME([result]) + N' AND ' 
		FROM 
			dda.[split_string](@pkColumns, N',', 1) 
		ORDER BY 
			row_id;

		SET @join = LEFT(@join, LEN(@join) - 4);
		SET @from = @from + @join;

		SET @sql = REPLACE(@sql, N'{AUDIT_COLUMNS}', @columnNames);
		SET @sql = REPLACE(@sql, N'{AUDIT_FROM}', @from);
	END;

	DECLARE @json nvarchar(MAX); 
	EXEC sp_executesql 
		@sql, 
		N'@json nvarchar(MAX) OUTPUT', 
		@json = @json OUTPUT;


	-- Define + Populate Key Info:
	SELECT
		@key = @key + CASE WHEN @operationType = N'INSERT' THEN N'[i].' ELSE N'[d].' END + QUOTENAME([result]) + N' [' + [result] + N'], '
	FROM 
		dda.[split_string](@pkColumns, N',', 1) 
	ORDER BY 
		row_id;

	SET @key = LEFT(@key, LEN(@key) -1);

	DECLARE @keyOutput nvarchar(MAX);
	SET @sql = N'SELECT @keyOutput = (SELECT ' + @key + N' FROM ' + CASE WHEN @operationType = N'INSERT' THEN N'#temp_inserted i' ELSE N'#temp_deleted d' END + N' FOR JSON PATH);';

	EXEC sp_executesql
		@sql, 
		N'@keyOutput nvarchar(MAX) OUTPUT', 
		@keyOutput = @keyOutput OUTPUT;
		
	-- Bind Key + Detail Elements (manually) into a new JSON object:
	SET @json = N'[{"key":' + @keyOutput + N', "detail":' + @json + N'}]';

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