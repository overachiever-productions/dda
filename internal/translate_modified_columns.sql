/*


*/

DROP FUNCTION IF EXISTS dda.translate_modified_columns;
GO

CREATE FUNCTION dda.[translate_modified_columns](@TargetTable sysname, @ChangeMap varbinary(1024)) 
RETURNS @changes table (column_id int NOT NULL, modified bit NOT NULL, column_name sysname NULL)
AS 
	-- {copyright}

	BEGIN 
		SET @TargetTable = NULLIF(@TargetTable, N'');
		IF @TargetTable IS NOT NULL BEGIN 
			DECLARE @object_id int = (SELECT OBJECT_ID(@TargetTable));

			-- Elegant bitwise manipulation from Jeffrey Yao via: https://www.mssqltips.com/sqlservertip/6497/how-to-identify-which-sql-server-columns-changed-in-a-update/ 

			IF EXISTS (SELECT NULL FROM sys.tables WHERE object_id = @object_id) BEGIN 
				DECLARE @currentMapSlot int = 1; 
				DECLARE @columnMask binary; 

				WHILE (@currentMapSlot < LEN(@ChangeMap) + 1) BEGIN 
					SET @columnMask = SUBSTRING(@ChangeMap, @currentMapSlot, 1);

					INSERT INTO @changes (column_id, modified)
					SELECT (@currentMapSlot - 1) * 8 + 1, @columnMask & 1 UNION ALL		
					SELECT (@currentMapSlot - 1) * 8 + 2, @columnMask & 2 UNION ALL 							   
					SELECT (@currentMapSlot - 1) * 8 + 3, @columnMask & 4 UNION ALL 							  
					SELECT (@currentMapSlot - 1) * 8 + 4, @columnMask & 8 UNION ALL 							   
					SELECT (@currentMapSlot - 1) * 8 + 5, @columnMask & 16 UNION ALL
					SELECT (@currentMapSlot - 1) * 8 + 6, @columnMask & 32 UNION ALL 
					SELECT (@currentMapSlot - 1) * 8 + 7, @columnMask & 64 UNION ALL 
					SELECT (@currentMapSlot - 1) * 8 + 8, @columnMask & 128
		
					SET @currentMapSlot = @currentMapSlot + 1;
				END;

				WITH column_names AS ( 
					SELECT [column_id], [name]
					FROM sys.columns 
					WHERE [object_id] = @object_id
				)
				UPDATE x 
				SET 
					x.column_name = c.[name]
				FROM 
					@changes x 
					INNER JOIN [column_names] c ON [x].[column_id] = [c].[column_id]
				WHERE 
					x.[column_name] IS NULL;

				DELETE FROM @changes WHERE [column_name] IS NULL;

			END;
		END;
		
		RETURN;
	END;
GO