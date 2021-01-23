/*


*/

DROP FUNCTION IF EXISTS dda.[split_string];
GO

CREATE FUNCTION [dda].[split_string](@serialized nvarchar(MAX), @delimiter nvarchar(20), @TrimResults bit)
RETURNS @Results TABLE (row_id int IDENTITY NOT NULL, result nvarchar(MAX))
AS 
	-- {copyright}

	BEGIN

	-- Code lifted from S4 (and, as such, is a DRY violation): https://github.com/overachiever-productions/s4/ 
	
	IF NULLIF(@serialized,'') IS NOT NULL AND DATALENGTH(@delimiter) >= 1 BEGIN
		IF @delimiter = N' ' BEGIN 
			-- this approach is going to be MUCH slower, but works for space delimiter... 
			DECLARE @p int; 
			DECLARE @s nvarchar(MAX);
			WHILE CHARINDEX(N' ', @serialized) > 0 BEGIN 
				SET @p = CHARINDEX(N' ', @serialized);
				SET @s = SUBSTRING(@serialized, 1, @p - 1); 
			
				INSERT INTO @Results ([result])
				VALUES(@s);

				SELECT @serialized = SUBSTRING(@serialized, @p + 1, LEN(@serialized) - @p);
			END;
			
			INSERT INTO @Results ([result])
			VALUES (@serialized);

		  END; 
		ELSE BEGIN

			DECLARE @MaxLength int = LEN(@serialized) + LEN(@delimiter);

			WITH tally (n) AS ( 
				SELECT TOP (@MaxLength) 
					ROW_NUMBER() OVER (ORDER BY o1.[name]) AS n
				FROM sys.all_objects o1 
				CROSS JOIN sys.all_objects o2
			)

			INSERT INTO @Results ([result])
			SELECT 
				SUBSTRING(@serialized, n, CHARINDEX(@delimiter, @serialized + @delimiter, n) - n) [result]
			FROM 
				tally 
			WHERE 
				n <= LEN(@serialized) AND
				LEN(@delimiter) <= LEN(@serialized) AND
				RTRIM(LTRIM(SUBSTRING(@delimiter + @serialized, n, LEN(@delimiter)))) = @delimiter
			ORDER BY 
				 n;
		END;

		IF @TrimResults = 1 BEGIN
			UPDATE @Results SET [result] = LTRIM(RTRIM([result])) WHERE DATALENGTH([result]) > 0;
		END;

	END;

	RETURN;
END;
GO