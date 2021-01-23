IF OBJECT_ID('dda.translation_columns') IS NULL BEGIN

	CREATE TABLE dda.translation_columns (
		[translation_column_id] int IDENTITY(1,1) NOT NULL, 
		[table_name] sysname NOT NULL, -- TODO: HAS to include schema - i.e., force a constraint or use a trigger... 
		[column_name] sysname NOT NULL, 
		[translated_name] sysname NOT NULL, 
		CONSTRAINT PK_translation_columns PRIMARY KEY NONCLUSTERED ([translation_column_id]) 
	); 

	CREATE CLUSTERED INDEX CLIX_translation_columns_by_table_and_column_name ON dda.[translation_columns] ([table_name], [column_name]);

END;