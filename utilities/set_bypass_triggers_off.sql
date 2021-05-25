/*


*/

IF OBJECT_ID('dda.set_bypass_triggers_off','P') IS NOT NULL
	DROP PROC dda.[set_bypass_triggers_off];
GO

CREATE PROC dda.[set_bypass_triggers_off]

AS
    SET NOCOUNT ON; 

	-- {copyright}
	
	/* Disallow Explicit User Transactions - i.e., triggers have to be 'turned on/off' outside of a user-enlisted TX: */
	IF @@TRANCOUNT > 0 BEGIN 
		RAISERROR(15002, 16, 1,'dda.bypass_dynamic_triggers');
		RETURN -1;
	END;

	/* If not a member of db_owner, can not execute... */
	IF NOT IS_ROLEMEMBER('db_owner') = 1 BEGIN
		RAISERROR('Procedure dda.bypass_dynamic_triggers may only be called by members of the db_owner role (including members of SysAdmin server-role).', 16, 1);
		RETURN -10;
	END;
	
	SET CONTEXT_INFO 0x0;

	RETURN 0;
GO