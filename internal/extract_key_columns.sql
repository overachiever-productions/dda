/*


*/

DROP PROC IF EXISTS dda.[extract_key_columns];
GO

CREATE PROC dda.[extract_key_columns]
	@TargetSchema				sysname				= N'dbo',
	@TargetTable				sysname, 
	@Output						nvarchar(MAX)		= N''	OUTPUT
AS
    SET NOCOUNT ON; 

	-- {copyright}
	
	DECLARE @columns nvarchar(MAX) = N'';
	DECLARE @objectName sysname = QUOTENAME(@TargetSchema) + N'.' + QUOTENAME(@TargetTable);

	SELECT  
		@columns = @columns + c.[name] + N', '
	FROM 
		sys.[indexes] i 
		INNER JOIN sys.[index_columns] ic ON i.[object_id] = ic.[object_id] AND i.[index_id] = ic.[index_id] 
		INNER JOIN sys.columns c ON ic.[object_id] = c.[object_id] AND ic.[column_id] = c.[column_id] 
	WHERE 
		i.[is_primary_key] = 1 
		AND i.[object_id] = OBJECT_ID(@objectName)
	ORDER BY 
		ic.[index_column_id]; 

	IF @columns <> N'' BEGIN 
		SET @columns = LEFT(@columns, LEN(@columns) - 1);
	  END;
	ELSE BEGIN 
		SELECT @columns = [serialized_surrogate_columns] 
		FROM dda.surrogate_keys
		WHERE [schema] = @TargetSchema AND [table] = @TargetTable;
	END;

	IF @Output IS NULL BEGIN 
		SET @Output = @columns;
	  END;
	ELSE BEGIN 
		SELECT @columns [Output]
	END;

	RETURN 0;
GO