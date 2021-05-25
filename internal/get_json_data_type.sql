/*

https://docs.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql?view=sql-server-ver15#return-value
Value of the Type column	JSON data type
0	null
1	string
2	number
3	true/false
4	array
5	object


				
				-- NULLS:
				SELECT dda.[get_json_data_type](NULL);
				SELECT dda.[get_json_data_type]('null'); 
				SELECT dda.[get_json_data_type]('NULL'); -- string


				SELECT dda.[get_json_data_type]('true');
				SELECT dda.[get_json_data_type]('True');  -- string (not boolean)
				SELECT dda.[get_json_data_type](325);
				SELECT dda.[get_json_data_type](325.00);
				SELECT dda.[get_json_data_type](-325);
				SELECT dda.[get_json_data_type](-325.99);
				SELECT dda.[get_json_data_type]('-325.99');
				SELECT dda.[get_json_data_type]('$325');
				SELECT dda.[get_json_data_type]('string here');

				SELECT dda.[get_json_data_type]('2020-10-20T13:48:39.567');
				SELECT dda.[get_json_data_type]('C7A3ED8B-AFE1-41BB-8ED9-F3777DA7D996');     


				SELECT dda.[get_json_data_type]('{
				  "my key $1": {
					"regularKey":{
					  "key with . dot": 1
					}
				  }
				}');


				SELECT dda.[get_json_data_type](N'[
				{
				"OrderNumber":"SO43659",
				"OrderDate":"2011-05-31T00:00:00",
				"AccountNumber":"AW29825",
				"ItemPrice":2024.9940,
				"ItemQuantity":1
				},
				{
				"OrderNumber":"SO43661",
				"OrderDate":"2011-06-01T00:00:00",
				"AccountNumber":"AW73565",
				"ItemPrice":2024.9940,
				"ItemQuantity":3
				}
				]');



*/


IF OBJECT_ID('dda.get_json_data_type','FN') IS NOT NULL
	DROP FUNCTION dda.[get_json_data_type];
GO

CREATE FUNCTION dda.[get_json_data_type] (@value nvarchar(MAX))
RETURNS tinyint
AS
    
	-- {copyright}
    
    BEGIN; 

		-- 0
		IF @value IS NULL RETURN 0;
		IF @value COLLATE SQL_Latin1_General_CP1_CS_AS = N'null' RETURN 0;
    	
		-- 3  true/false must be lower-case to equate to boolean values - otherwise, it's a string. 
    	IF @value COLLATE SQL_Latin1_General_CP1_CS_AS IN ('true', 'false') RETURN 3;

		-- 2
		IF @value = N'' RETURN 1; 
		IF @value NOT LIKE '%[^0123456789.-]%' RETURN 2; 

		-- 4 & 5
    	IF ISJSON(@value) = 1 BEGIN 
			IF LEFT(LTRIM(@value), 1) = N'[' RETURN 4; 

			RETURN 5;
		END;

    	-- at this point, there's nothing left but string... 
    	RETURN 1;
    
    END;
GO