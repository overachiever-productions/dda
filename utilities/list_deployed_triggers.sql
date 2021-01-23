DROP PROC IF EXISTS dda.list_deployed_triggers; 
GO 

CREATE PROC dda.list_deployed_triggers 

AS 
	SET NOCOUNT ON; 

	-- {copyright}

	SELECT 
		(SELECT QUOTENAME(SCHEMA_NAME(o.[schema_id])) + N'.' + QUOTENAME(OBJECT_NAME(o.[object_id])) FROM sys.objects o WHERE o.[object_id] = t.[parent_id]) [parent_table],
		(SELECT QUOTENAME(SCHEMA_NAME(o.[schema_id])) + N'.' + QUOTENAME(t.[name]) FROM sys.objects o WHERE o.[object_id] = t.[object_id]) [trigger_name],
		(SELECT CASE WHEN EXISTS (SELECT NULL FROM sys.[trigger_events] e WHERE e.[object_id] = t.[object_id] AND [e].[type] = 1) THEN 1 ELSE 0 END) [for_insert],
		(SELECT CASE WHEN EXISTS (SELECT NULL FROM sys.[trigger_events] e WHERE e.[object_id] = t.[object_id] AND [e].[type] = 2) THEN 1 ELSE 0 END) [for_update],
		(SELECT CASE WHEN EXISTS (SELECT NULL FROM sys.[trigger_events] e WHERE e.[object_id] = t.[object_id] AND [e].[type] = 3) THEN 1 ELSE 0 END) [for_delete],
		[t].[is_disabled],
		[t].[create_date],
		[t].[modify_date],
		[t].[object_id] [trigger_object_id],
		[t].[parent_id] [parent_table_id]
	FROM 
		sys.triggers t
		INNER JOIN sys.[extended_properties] p ON t.[object_id] = p.[major_id]
	WHERE 
		p.[name] = N'DDATrigger' AND p.[value] = 'true';


	RETURN 0;
GO