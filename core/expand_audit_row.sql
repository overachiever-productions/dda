/*
	
	Use-Case:
		- Audits / Triggers are deployed and capturing data. 
		- There isn't yet a GUI for reviewing audit data (or an admin/dev/whatever is poking around in the database). 
		- User is capable of running sproc commands (e.g., EXEC dda.get_audit_data to find a couple of rows they'd like to see)
		- But, they're not wild about trying to view change details crammed into JSON. 

		This sproc lets a user query a single audit row, and (dynamically) 'explodes' the JSON data for easier review. 

		Further, the option to transform (or NOT) the data is present as well (useful for troubleshooting/debugging app changes and so on). 


	EXEC dda.expand_audit_row
		@AuditId = 1109, 
		@TransformOutput = 0;



	POTENTIAL change to display options. 
		MIGHT make more sense to use a multi-result-set approach to displaying the output of this sproc. 
			e.g.,
				1. raw trace data as a set of results. 
				2. translated/exploded capture data.... as the second set. 
				3. if/when row is an UPDATE... then we'd have 2x results sets for [2] - so 2 & 3. 


	SOME OTHER ODD ideas:
		would it be possible to somehow create a TVF that would enable JOINs against the parent/root table and ... dda.audits WHERE table = @TableNameToQuery
			I would HAVE to 'know' the (Pimary/surrogate) Key details to manage that JOIN... 
				but... if I've got the @TableName ... i can/could derive that info - right? 
				yeah... pretty sure I could. 



*/

DROP PROC IF EXISTS dda.expand_audit_row; 
GO 

CREATE PROC dda.expand_audit_row 
	@AuditId					int, 
	@TransformOutput			bit		= 1
AS 
	SET NOCOUNT ON; 

	-- {copyright}

	CREATE TABLE #results ( 
		[row_number] int NOT NULL,
		[total_rows] int NOT NULL, 
		[audit_id] int NOT NULL,
		[timestamp] datetime NOT NULL,
		[user] sysname NOT NULL,
		[table] sysname NOT NULL,
		[transaction_id] sysname NOT NULL,
		[operation_type] char(6) NOT NULL,
		[row_count] int NOT NULL,
		[change_details] nvarchar(max) NULL
	);

	INSERT INTO [#results] (
		[row_number],
		[total_rows],
		[audit_id],
		[timestamp],
		[user],
		[table],
		[transaction_id],
		[operation_type],
		[row_count],
		[change_details]
	)
	EXEC dda.[get_audit_data]
		@AuditID = @AuditId,
		@TransformOutput = @TransformOutput,
		@FromIndex = 1,
		@ToIndex = 1;

	DECLARE @operationType char(6);
	DECLARE @rowCount int; 
	DECLARE @json nvarchar(MAX);
	DECLARE @objectName sysname;

	SELECT 
		@operationType = [operation_type], 
		@rowCount = [row_count], 
		@json = [change_details], 
		@objectName = [table]
	FROM 
		[#results]

	IF @TransformOutput = 1 BEGIN
		-- account for mappings/translations of table-names:
		SELECT @objectName = [table_name] FROM dda.[translation_tables] WHERE [translated_name] = @objectName;
	END

	-- Get a list of covered/included columns. (For INSERT/DELETE this should be 'everything' (all columns) BUT.. THERE may have been schema changes/etc. 
	CREATE TABLE [#current_columns] (
		row_id int IDENTITY(1,1) NOT NULL, 
		column_name sysname NOT NULL, 
		data_type sysname NOT NULL, 
		max_length int NOT NULL, 
		[precision] int NOT NULL, 
		scale int NOT NULL
	);
	
	INSERT INTO [#current_columns] (
		[column_name],
		[data_type],
		[max_length],
		[precision],
		[scale]
	)
	SELECT
		c.[name] [column_name], 
		t.[name] [data_type],
		c.[max_length], 
		c.[precision], 
		c.[scale]
	FROM
		[sys].[columns] c
		LEFT OUTER JOIN sys.types t ON [c].[system_type_id] = [t].[system_type_id]
	WHERE 
		[c].[object_id] = OBJECT_ID(@objectName);

	CREATE TABLE #json_columns (
		row_id int IDENTITY(1,1) NOT NULL, 
		column_name sysname NOT NULL, 
		json_type int NOT NULL 
	);

	INSERT INTO [#json_columns] (
		[column_name],
		[json_type]
	)
	SELECT 
		y.[Key] [column_name], 
		y.[Type] [json_type]
	FROM 
		[#results] x
		OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], '$[0].detail'), '$') z
		CROSS APPLY OPENJSON(z.[Value], N'$') y
	WHERE 
		y.[Key] IS NOT NULL 
		AND y.[Value] IS NOT NULL;

	DECLARE @expansionQuery nvarchar(MAX) = N'SELECT * FROM #results;'

	EXEC sp_executesql @expansionQuery;

	RETURN 0;


	IF UPPER(@operationType) IN ('INSERT', 'DELETE') BEGIN 

		-- For INSERT/DELETE, any columns in #json_columns that are NOT IN [#current_columns] will become sqlvariants.... and... name will be [columnName*] -- meaining... translated as sqlvariant.
		-- AND, may(?) want to ALSO assume and process rules such that any column CURRENTLY defined against the table will be loaded as NULL or <MISSING> or something like that... 

/*
Working example from AfdDB:
						SELECT 
							a.[audit_id],
							a.[timestamp],
							a.[schema],
							a.[table],
							a.[user],
							a.[operation],
							a.[transaction_id],
							a.[row_count],
							a.[audit], 
							y.*
						FROM 
							dda.[audits] a
							CROSS APPLY OPENJSON(JSON_QUERY([a].[audit], N'$')) x
							CROSS APPLY OPENJSON(x.[Value], N'$.detail') WITH (UserName sysname '$.UserName', Action sysname '$.Action') y
						WHERE 
							a.[audit_id] = 292;


				and another:


						SELECT 
							a.[audit_id],
							a.[timestamp],
							a.[schema],
							a.[table],
							a.[user],
							a.[operation],
							a.[transaction_id],
							a.[row_count],
							a.[audit], 
							y.*, 
							z.*
						FROM 
							dda.[audits] a
							CROSS APPLY OPENJSON(JSON_QUERY([a].[audit], N'$')) x
							CROSS APPLY OPENJSON(x.[Value], N'$.detail') WITH (UserName sysname '$.UserName', Action sysname '$.Action') y
							CROSS APPLY OPENJSON(x.[Value], N'$.key') WITH (AuditIndex int N'$.AuditIndex') z
						WHERE
							a.[table] = N'AUDIT'
							AND z.[AuditIndex] > 440;



That's a DIRECT query against dda.audits - with just 2x columns that i'm extracting... but the structure is correct:
	I'm first burrowing down into EACH ROW (x)
	Then, from there, i'm shredding details per each row. 


Here's a similar query against a 3x INSERT against Meddling.dbo.SortTable:

						SELECT 
							[a].[audit_id],
							[a].[timestamp],
							[a].[schema],
							[a].[table],
							[a].[user],
							[a].[operation],
							[a].[transaction_id],
							[a].[row_count], 
							[x].[Key] [json_row], 
	
							[y].[OrderID],
							[y].[CustomerID],
							[y].[Value],
							[y].[ColChar]
						FROM 
							dda.[audits] a 
							CROSS APPLY OPENJSON(JSON_QUERY([a].[audit], N'$')) x
							CROSS APPLY OPENJSON(x.[Value], N'$.detail') WITH (
								OrderID				int					N'$.OrderID',
								CustomerID			int					N'$.CustomerID', 
								[Value]				decimal(18,2)		N'$.Value',
								ColChar				char(500)			N'$.ColChar'
							) y
						WHERE 
							a.[audit_id] = 1109; -- 3 rows... 

	where i'm going to have to, clearly, define/derive: 
		a. the list of [y].col-names-to-select-from-the-main-cross-apply
		b. the definitions of the columns in the WITH () clause... 



	ANd, of course, an UPDATE becomes a lot harder - as it'll be 2 'sets' of queries... 
		i.e., something like the above but for, say, $.OrderID.from and $.OrderID.to - into, effectively, different results sets...so'z I can show before/after

		And, here's an example of an UPDATE (getting the FROM values):

						SELECT 
							[a].[audit_id],
							[a].[timestamp],
							[a].[schema],
							[a].[table],
							[a].[user],
							[a].[operation],
							[a].[transaction_id],
							[a].[row_count], 
							[x].[Key] [json_row], 
	
							[y].[Value],
							[y].[ColChar]

							,a.[audit]
						FROM 
							dda.[audits] a 
							CROSS APPLY OPENJSON(JSON_QUERY([a].[audit], N'$')) x
							CROSS APPLY OPENJSON(x.[Value], N'$.detail') WITH (
								[Value]				decimal(18,2)		N'$.Value.from',
								ColChar				char(500)			N'$.ColChar.from'
							) y
						WHERE 
							a.[audit_id] = 1013; -- 1 row


		Nothing too terrible... 



*/



		SET @expansionQuery = N'

		SELECT 
			r.audit_id, 
			r.[timestamp], 
			r.[user], 
			r.[table], 
			r.[total_rows], 
			r.[operation_type], 
			'' '' [ ], -- divider... 
			x.*  -- i..e, one entry per ''row''
		FROM 
			[#results] r
			INNER JOIN (
				SELECT 
					* OR {column_names} -- probably column_names cuz I''ll need to change some of them to columnName* (or potentially change them) if/when they''re sqlvariants... 
				FROM 
					OPENJSON(@json)
				WITH (
					{column_name	datatype    ''$.detail[0].{columnName''},
					{column_name	datatype    ''$.detail[0].{columnName''},
					{column_name	datatype    ''$.detail[0].{columnName''},
					{column_name	datatype    ''$.detail[0].{columnName''},
					{etc}
				)
			) x -- hmmm... what''s the JOIN here? 
		';

	  END;
	ELSE BEGIN -- UPDATE, ROTATE, or MUTATE


		SET @expansionQuery = N'SELECT {stuff as above - but for DELETED and, i guess, change column names to previous.{ColumnName} - where ... path = $detail[0].N.{from} ONLY}
		
		UNION -- OR just run a totally SECOND select - i.e., 2x distinct selects)
		
		SELECT {same-ish, but only for $.detail[0].N.{to} values instead...}
		';





		-- for UPDATEs, we just want a list of columns in the JSON. But, for any columns not in #json_columns, ... load as sqlvariant.


		---- get a list of columns 'covered' in the UPDATE:
		--SELECT 
		--	[y].[Key] [column] 
		--FROM 
		--	[#results] x
		--	OUTER APPLY OPENJSON(JSON_QUERY([x].[change_details], '$[0].detail'), '$') z
		--	CROSS APPLY OPENJSON(z.[Value], N'$') y
		--WHERE 
		--	y.[Key] IS NOT NULL 
		--	AND y.[Value] IS NOT NULL;
	END;


	-- run exec sp_executesql 
	-- but do it in a try/catch. 

	-- if we fail, retry with all columns as ... sqlvariant... then... if that fails, throw an error. 


	RETURN 0;
GO