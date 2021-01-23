--##OUTPUT: \\Deployment
--##NOTE: This is a build file only (i.e., it stores upgade/install directives + place-holders for code to drop into dda, etc.)
/*

	REFERENCE:
		- License, documentation, and source code at: 
			https://github.com/overachiever-productions/dda/


*/



-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
/*


!!!! WARNING


-- 0. Make sure to run the following commands in the database you wish to target for audits (i.e., not master or any other db you might currently be in).
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- */


USE [your database here];
GO


----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 1. Create dda schema:
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------


-- TODO: IF checks + exceptions if already exists
--IF SCHEMA_ID('dda') IS NOT NULL BEGIN
--	RAISERROR('WARNING: dda schema already exists - execution is being terminated and connection will be broken.', 21, 1) WITH LOG;
--END;
--GO 


IF SCHEMA_ID('dda') IS NULL BEGIN 
	EXEC('CREATE SCHEMA [dda] AUTHORIZATION [db_owner];');
END;
GO 

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 2. Core Tables:
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------

IF OBJECT_ID('dda.version_history', 'U') IS NULL BEGIN

	CREATE TABLE dda.version_history (
		version_id int IDENTITY(1,1) NOT NULL, 
		version_number varchar(20) NOT NULL, 
		[description] nvarchar(200) NULL, 
		deployed datetime NOT NULL CONSTRAINT DF_version_info_deployed DEFAULT GETDATE(), 
		CONSTRAINT PK_version_info PRIMARY KEY CLUSTERED (version_id)
	);

	EXEC sys.sp_addextendedproperty
		@name = 'dda',
		@value = 'TRUE',
		@level0type = 'Schema',
		@level0name = 'dda',
		@level1type = 'Table',
		@level1name = 'version_history';
END;

-----------------------------------
--##INCLUDE: tables\translation_tables.sql

-----------------------------------
--##INCLUDE: tables\translation_columns.sql

-----------------------------------
--##INCLUDE: tables\translation_values.sql

-----------------------------------
--##INCLUDE: tables\trigger_host.sql

-----------------------------------
--##INCLUDE: tables\surrogate_keys.sql

-----------------------------------
--##INCLUDE: tables\audits.sql


----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 3. <Placeholder for Cleanup / Refactor from Previous Versions>:
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------



----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 4. Deploy new/updated code.
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------------------------------------
-- Meta-Data and Capture-Related Functions
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
--##INCLUDE: internal\split_string.sql

-----------------------------------
--##INCLUDE: internal\translate_modified_columns.sql


------------------------------------------------------------------------------------------------------------------------------------------------------
-- DDA Trigger 
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
--##INCLUDE: core\dynamic_data_auditing_trigger.sql

------------------------------------------------------------------------------------------------------------------------------------------------------
-- Search/View
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
--##INCLUDE: core\get_audit_data.sql

-----------------------------------
--##INCLUDE: core\get_audit_row.sql

------------------------------------------------------------------------------------------------------------------------------------------------------
-- Utilities:
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
--##INCLUDE: utilities\enable_table_auditing.sql

-----------------------------------
--##INCLUDE: utilities\update_trigger_definitions.sql

-----------------------------------
--##INCLUDE: utilities\list_deployed_triggers.sql

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 5. Update version_history with details about current version (i.e., if we got this far, the deployment is successful). 
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DECLARE @CurrentVersion varchar(20) = N'##{{dda_version}}';
DECLARE @VersionDescription nvarchar(200) = N'##{{dda_version_summary}}';
DECLARE @InstallType nvarchar(20) = N'Install. ';

IF EXISTS (SELECT NULL FROM dda.[version_history] WHERE CAST(LEFT(version_number, 3) AS decimal(2,1)) >= 4)
	SET @InstallType = N'Update. ';

SET @VersionDescription = @InstallType + @VersionDescription;

-- Add current version info:
IF NOT EXISTS (SELECT NULL FROM dda.version_history WHERE [version_number] = @CurrentVersion) BEGIN
	INSERT INTO dda.version_history (version_number, [description], deployed)
	VALUES (@CurrentVersion, @VersionDescription, GETDATE());
END;
GO

-----------------------------------
SELECT * FROM dda.version_history;
GO