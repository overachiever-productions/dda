USE [dda_test]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [transformations].[test ensure_test_setup]
AS
BEGIN
	-- Arrange:
	EXEC [tSQLt].[FakeTable] 
		@TableName = N'audits', 
		@SchemaName = N'dda';
	
	INSERT INTO dda.[audits] (
		[audit_id],
		[timestamp],
		[schema],
		[table],
		[user],
		[operation],
		[transaction_id],
		[row_count],
		[audit]
	)
	VALUES	
	(
		19,
		'2021-01-28 15:37:41.667',
		N'dbo', 
		N'SortTable', 
		'sa', 
		'DELETE', 
		34827897, 
		1, 
		N'[{"key":[{"OrderID":30,"CustomerID":74}],"detail":[{"OrderID":30,"CustomerID":74,"OrderDate":"2020-10-20T13:48:39.567","Value":1873.62,"ColChar":"C7A3ED8B-AFE1-41BB-8ED9-F3777DA7D996                                                                                                                                                                                                                                                                                                                                                                                                                                                                                "}]}]' 
	), 
	(
		20,
		'2021-01-28 15:40:10.093',
		N'dbo', 
		N'SortTable', 
		'sa', 
		'INSERT', 
		34869927, 
		1, 
		N'[{"key":[{"OrderID":100027,"CustomerID":845}],"detail":[{"OrderID":100027,"CustomerID":845,"OrderDate":"2021-01-28T15:40:10.077","Value":99.60,"ColChar":"0xxxxx9945                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          "}]}]' 
	), 
	(
		1008,
		'2021-02-02 16:07:44.363',
		N'dbo', 
		N'SortTable', 
		'sa', 
		'UPDATE', 
		1812392, 
		3, 
		N'[{"key":[{"OrderID":249,"CustomerID":83}],"detail":[{"OrderDate":{"from":"2011-07-12T13:48:39.567","to":"2021-02-02T16:07:44.330"},"Value":{"from":1995.81,"to":33.99}}]},{"key":[{"OrderID":247,"CustomerID":178}],"detail":[{"OrderDate":{"from":"2016-04-14T13:48:39.567","to":"2021-02-02T16:07:44.330"},"Value":{"from":1886.08,"to":33.99}}]},{"key":[{"OrderID":246,"CustomerID":151}],"detail":[{"OrderDate":{"from":"2020-02-10T13:48:39.567","to":"2021-02-02T16:07:44.330"},"Value":{"from":1768.17,"to":33.99}}]}]' 
	);


	-- Act: 
	DECLARE @count int; 
	SELECT @count = COUNT(*) FROM dda.[audits];

	-- Assert: 
	EXEC [tSQLt].[AssertEquals] 3, @count;
	 
END;