/*



*/

DROP PROC IF EXISTS dda.update_trigger_definitions; 
GO 

CREATE PROC dda.update_trigger_definitions 

	-- could add exclusions here, but I don't think that makes sense - i.e., either we update ALL triggers or ... none. 

AS 
	SET NOCOUNT ON; 

	-- {copyright}

	-- foreach trigger defined as a DDATrigger via Extended events: 
	--		get the NEW definition from the dda.trigger_host table. 
	--			extract down to the definition... 
	--			wire up an ALTER... 
	--			execute within a TRY/CATCH. 
	--		PRINT out a list of which triggers - if any, FAILED updates and recommend DROP + RECREATE via ... EXEC dda.enable_table_auditing @paramsHere + @ForceReplacement = N'REPLACE';