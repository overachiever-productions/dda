IF OBJECT_ID('dda.translation_tables') IS NULL BEGIN

	CREATE TABLE dda.translation_tables (
		[translation_table_id] int IDENTITY(1,1) NOT NULL, 
		[table_name] sysname NOT NULL, -- TODO: HAS to include schema - i.e., force a constraint or use a trigger... 
		[translated_name] sysname NOT NULL, 
		CONSTRAINT PK_translation_tables PRIMARY KEY NONCLUSTERED ([translation_table_id])
	); 

	CREATE UNIQUE CLUSTERED INDEX CLIX_translation_tables_by_table_name ON [dda].[translation_tables] ([table_name]);

END;