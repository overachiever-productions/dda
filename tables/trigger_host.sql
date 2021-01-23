IF OBJECT_ID('dda.trigger_host') IS NULL BEGIN

	CREATE TABLE dda.trigger_host (
		[notice] sysname NOT NULL 
	); 

	INSERT INTO dda.trigger_host ([notice]) VALUES (N'Table REQUIRED: provides TEMPLATE for triggers.');

END;