
CREATE OR ALTER PROCEDURE [projection].[test intersecting_users_and_txids_restricts_results]
AS
BEGIN
  	-----------------------------------------------------------------------------------------------------------------
	-- Arrange:
	-----------------------------------------------------------------------------------------------------------------
	EXEC [tSQLt].[FakeTable] 
		@TableName = N'dda.audits';
	
	INSERT INTO dda.[audits] (
		[audit_id],
		[timestamp],
		[schema],
		[table],
		[original_login],
		[operation],
		[transaction_id],
		[row_count],
		[audit]
	)
	VALUES
	(
		1117, 
		N'2021-05-13 07:16:53.587', 
		N'dbo', 
		N'login_metrics', 
		N'mikec', 
		N'UPDATE', 
		38228873, 
		4, 
		N'[{"key":[{"row_id":650}],"detail":[{"entry_date":{"from":"2019-11-26T18:08:44.180","to":"2019-12-26T18:08:44.180"}}]},{"key":[{"row_id":649}],"detail":[{"entry_date":{"from":"2019-11-26T18:08:44.117","to":"2019-12-26T18:08:44.117"}}]},{"key":[{"row_id":648}],"detail":[{"entry_date":{"from":"2019-11-26T18:08:22.820","to":"2019-12-26T18:08:22.820"}}]},{"key":[{"row_id":647}],"detail":[{"entry_date":{"from":"2019-11-26T18:08:09.443","to":"2019-12-26T18:08:09.443"}}]}]'
	),
	(
		1118, 
		N'2021-05-13 07:18:00.987', 
		N'dbo', 
		N'login_metrics', 
		N'sa', 
		N'UPDATE', 
		38229788, 
		4, 
		N'[{"key":[{"row_id":650}],"detail":[{"operation_type":{"from":"CL","to":"DL"}}]},{"key":[{"row_id":649}],"detail":[{"operation_type":{"from":"CL","to":"DL"}}]},{"key":[{"row_id":648}],"detail":[{"operation_type":{"from":"DL","to":"CL"}}]},{"key":[{"row_id":647}],"detail":[{"operation_type":{"from":"DL","to":"CL"}}]}]'
	),
	(
		1119, 
		N'2021-05-13 07:22:08.940', 
		N'dbo', 
		N'login_metrics', 
		N'mikec', 
		N'INSERT', 
		38252253, 
		2, 
		N'[{"key":[{"row_id":5452}],"detail":[{"row_id":5452,"entry_date":"2019-11-26T18:28:44.580","operation_type":"DL","batch_size":20,"login_creation_time_ms":140,"count_of_sys_principals":3633}]},{"key":[{"row_id":5451}],"detail":[{"row_id":5451,"entry_date":"2019-11-26T18:28:44.440","operation_type":"DL","batch_size":20,"login_creation_time_ms":140,"count_of_sys_principals":3653}]}]'
	),
	(
		1120, 
		N'2021-05-13 07:29:31.050', 
		N'dbo', 
		N'SortTable', 
		N'billm', 
		N'UPDATE', 
		38330595, 
		1, 
		N'[{"key":[{"OrderID":98,"CustomerID":138}],"detail":[{"ColChar":{"from":"61C32AAB-9528-4B1F-AC30-936C2C72C312                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ","to":"0xSecretInfoHere                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    "}}]}]'
	),
	(
		1121, 
		N'2021-05-25 11:55:51.777', 
		N'dbo', 
		N'Errors', 
		N'sayidk', 
		N'UPDATE', 
		5589718, 
		1, 
		N'[{"key":[{"ErrorID":31}],"detail":[{"ErrorMessage":{"from":"Test Error Here","to":"Modified without bypass"}}]}]'
	),
	(
		1122, 
		N'2021-06-25 13:01:45.897', 
		N'dbo', 
		N'SortTable', 
		N'sa', 
		N'INSERT', 
		49491372, 
		4, 
		N'[{"key":[{"OrderID":101049,"CustomerID":30}],"detail":[{"OrderID":101049,"CustomerID":30,"OrderDate":"2021-06-25T13:01:45.867","Value":2268.33,"ColChar":"aaaa_aaaa                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           "}]},{"key":[{"OrderID":101048,"CustomerID":30}],"detail":[{"OrderID":101048,"CustomerID":30,"OrderDate":"2021-06-25T13:01:45.867","Value":2258.33,"ColChar":"zzzzz_zzzz                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          "}]},{"key":[{"OrderID":101047,"CustomerID":28}],"detail":[{"OrderID":101047,"CustomerID":28,"OrderDate":"2021-06-25T13:01:45.867","Value":1187.33,"ColChar":"yyyy_yyyy                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           "}]},{"key":[{"OrderID":101046,"CustomerID":27}],"detail":[{"OrderID":101046,"CustomerID":27,"OrderDate":"2021-06-25T13:01:45.867","Value":999.33,"ColChar":"xxxx_xxxx                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           "}]}]'                       
	);

	DROP TABLE IF EXISTS #search_output;

	CREATE TABLE #search_output ( 
		[row_number] int NOT NULL,
		[total_rows] int NOT NULL, 
		[audit_id] int NOT NULL,
		[timestamp] datetime NOT NULL,
		[original_login] sysname NOT NULL,
		[transaction_id] sysname NOT NULL,
		[table] sysname NOT NULL,
		[operation_type] char(9) NOT NULL,
		[row_count] int NOT NULL,
		[change_details] nvarchar(max) NULL, 
	);

	-----------------------------------------------------------------------------------------------------------------
	-- Act: 
	-----------------------------------------------------------------------------------------------------------------
	INSERT INTO [#search_output] (
		[row_number],
		[total_rows],
		[audit_id],
		[timestamp],
		[original_login],
		[table],
		[transaction_id],
		[operation_type],
		[row_count],
		[change_details]
	)
	EXEC dda.[get_audit_data]
		@TargetLogins = N'sa, sayidk', 
		@StartTransactionID = 49491372, 
		@TransactionDate = '2021-06-25';

	-----------------------------------------------------------------------------------------------------------------
	-- Assert: 
	-----------------------------------------------------------------------------------------------------------------
	DECLARE @rowCount int = (SELECT COUNT(*) FROM [#search_output]); 
	EXEC [tSQLt].[AssertEquals] @Expected = 1, @Actual = @rowCount;

END;