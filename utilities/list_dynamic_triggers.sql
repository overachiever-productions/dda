DROP PROC IF EXISTS dda.list_dynamic_triggers; 
GO 

CREATE PROC dda.list_dynamic_triggers 

AS 
	SET NOCOUNT ON; 

	-- {copyright}

	WITH core AS ( 
		SELECT 
			(SELECT QUOTENAME(SCHEMA_NAME(o.[schema_id])) + N'.' + QUOTENAME(OBJECT_NAME(o.[object_id])) FROM sys.objects o WHERE o.[object_id] = t.[parent_id]) [parent_table],
			(SELECT QUOTENAME(SCHEMA_NAME(o.[schema_id])) + N'.' + QUOTENAME(t.[name]) FROM sys.objects o WHERE o.[object_id] = t.[object_id]) [trigger_name],
			CAST(p.[value] AS sysname) [trigger_version],
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
			p.[name] = N'DDATrigger' AND p.[value] IS NOT NULL
			AND 
				-- don't show the dynamic trigger TEMPLATE - that'll just cause confusion:
				t.[parent_id] <> (SELECT [object_id] FROM sys.objects WHERE [schema_id] = SCHEMA_ID('dda') AND [name] = N'trigger_host')
	) 
	
	SELECT 
		c.[parent_table],
		c.[trigger_name],
		c.[trigger_version],
		x.[definition] [custom_trigger_logic],
		c.[for_insert],
		c.[for_update],
		c.[for_delete],
		c.[is_disabled],
		c.[create_date],
		c.[modify_date],
		c.[trigger_object_id],
		c.[parent_table_id]
	FROM 
		[core] c
		CROSS APPLY dda.[extract_custom_trigger_logic](c.[trigger_name]) x

	RETURN 0;
GO