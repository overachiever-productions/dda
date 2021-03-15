/*

*/

DROP FUNCTION IF EXISTS dda.extract_custom_trigger_logic;
GO

CREATE FUNCTION dda.[extract_custom_trigger_logic](@TriggerName sysname)
RETURNS @output table ([definition] nvarchar(MAX) NULL) 
AS 
	-- {copyright}

	BEGIN 
		DECLARE @body nvarchar(MAX); 
		SELECT @body = [definition] FROM sys.[sql_modules] WHERE [object_id] = OBJECT_ID(@TriggerName);

		DECLARE @start int, @end int; 
		SELECT 
			@start = PATINDEX(N'%--~~ ::CUSTOM LOGIC::start%', @body),
			@end = PATINDEX(N'%--~~ ::CUSTOM LOGIC::end%', @body);

		DECLARE @logic nvarchar(MAX);
		SELECT @logic = REPLACE(SUBSTRING(@body, @start, @end - @start), N'--~~ ::CUSTOM LOGIC::start', N'');

		DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10);
		DECLARE @whitespaceOnly sysname = N'%[^ ' + NCHAR(9) + @crlf + N']%';

		IF PATINDEX(@whitespaceOnly, @logic) = 0 SET @logic = NULL;

		INSERT INTO @output (
			[definition]
		)
		VALUES	(
			@logic
		);

		RETURN;
	END;
GO
