/*
	
	Use-Case:
		- Audits / Triggers are deployed and capturing data. 
		- There isn't yet a GUI for reviewing audit data (or an admin/dev/whatever is poking around in the database). 
		- User is capable of running sproc commands (e.g., EXEC dda.get_audit_data to find a couple of rows they'd like to see)
		- But, they're not wild about trying to view change details crammed into JSON. 

		This sproc lets a user query a single audit row, and (dynamically) 'explodes' the JSON data for easier review. 

		Further, the option to transform (or NOT) the data is present as well (useful for troubleshooting/debugging app changes and so on). 

*/

DROP PROC IF EXISTS dda.get_audit_row; 
GO 

CREATE PROC dda.get_audit_row 
	@AuditId					int, 
	@TransformOutput			bit		= 1
AS 
	SET NOCOUNT ON; 

	-- {copyright}

	SELECT 'Not implemented yet.' [status];

	RETURN 0;
GO