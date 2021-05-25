--##OUTPUT: \\Deployment
--##NOTE: This is a build file only (i.e., it stores upgade/install directives + place-holders for code to drop into dda, etc.)
/*

		I N S T R U C T I O N S

			INSTALL
				1. RUN. 
				2. CONFIGURE. 
			
			
			UPDATE:
				1. RUN. 
				2. UPDATE. 



			I N S T A L L
				1. RUN
					- Make sure you've opened this script in/against the database you wish to target (i.e., not master, or some other database, etc).
					- Use SECTION 0 if/as needed (you can comment it out or change it - whatever suits your needs). 
					- Once you're connected, in your target database, execute this entire script (i.e., F5). 

				2. CONFIGURE
					- Determine which tables you'd like to EXPLICITLY track for auditing changes (i.e., dda only works against explicitly targeted tables).
						NOTE: 
							- ONLY tables with an explicit PK (constraint) can be audited. (Tables without a PK are 'spreadsheets', even if they live in SQL Server).
							- You can create temporary 'work-arounds' for tables without PKs by adding rows to dda.surrogate_keys. 
							- Attempting to 'tag' a table for auditing without a PK will result in an error - i.e., dda logic will require surrogate keys or a PK. 


					- If you ONLY want to audit a FEW tables, use dda.enable_table_auditing - called 1x per EACH table you wish to audit:

								For example, if you have a [Users] table with an existing PK, you'd run the following: 

											EXEC dda.[enable_table_auditing] 
												@TargetSchema = N'dbo',   -- defaults to dbo if NOT specified (i.e., NOT needed for dbo.owned-tables).
												@TargetTable = N'Users';


								And, if you had an [Events] 'table' without an explicitly defined PK, you could define a SURROGATE key
									as part of the setup process for enabling auditing against this table, like so: 

											EXEC dda.[enable_table_auditing]  
												@TargetTable = N'Events', 
												@SurrogateKeys = N'EventCategory, EventID';  -- DDA will treat these two columns as IF they were an explicit PK (for row Identification).



					- If you want to audit MOST/ALL tables, use dda.enable_database_auditing - called 1x for an entire database - WITH OPTIONS to exclude specific tables. 
						
								For example, assume you have 35 tables in your database - and that you wish to track/audit all but 3 of them: 

												EXEC dda.[enable_database_auditing] 
													@ExcludedTables = N'Calendar, DateDimensions, StaticFields';


								And/or if some of your 35 tables (other than the 3 listed above) do NOT have PKs and you wish to 'skip' them for now (or forever): 


												EXEC dda.[enable_database_auditing] 
													@ExcludedTables = N'Calendar, DateDimensions, StaticFields', 
													@ExcludeTablesWithoutPKs = 1;

										Then, the @ExcludeTablesWithoutPKs parameter will let you skip all tables that CANNOT be audited without either adding a PK or surrogate-key defs. 
											NOTE: if you skip/exclude tables via the @ExcludeTablesWithoutPKs parameter, a report of all skipped tables will be output at the end of execution.

					- for BOTH dda.enable_table_auditing and dda.enable_database_auditing, you CAN specify the format/naming-structure for deployed triggers
						by using the @TriggerNamePattern - which uses the {0} token as a place-holder for your specific table-name. 

								For example:
									- if I have 3 tables in my database: Widgets, Users, and Events
									- and I specify
											@TriggerNamePattern = N'auditing_trigger_for_{0}'

									- then the following trigger names will be applied/created (respectively) for the tables listed above: 
													auditing_trigger_for_Widgets
													auditing_trigger_for_Users
													auditing_trigger_for_Events


			U P D A T E
				1. RUN
					- Make sure you've opened this script in/against the database you wish to target (i.e., not master, or some other database, etc).
					- Use SECTION 0 if/as needed (you can comment it out or change it - whatever suits your needs). 
					- Once you're connected, in your target database, execute this entire script (i.e., F5). 

				2. UPDATE
					- the DDA setup/update script (executed in step 2) will determine if there are new changes (updated logic) for the dda triggers already deployed into your environment. 
						- IF there are NO logic changes available for your deployed/existing triggers, you're done. 
												
						- IF THERE ARE changes, you'll be prompted/alerted to run dda.update_trigger_definitions. 

								BY DEFAULT, execution of this sproc will set @PrintOnly = 1 - meaning it will SHOW you what it WOULD do if executed (@PrintOnlyy = 0). 
								This gives you a chance to visually review which triggers will be updated. 


								Or in other words:
										a. run the following to review changes: 

													EXEC dda.[update_trigger_definitions]

										b. run the following to IMPLEMENT trigger change/updates against all of your deployed triggers: 

													EXEC dda.[update_trigger_definitions] @PrintOnly = 0;

						

		R E F E R E N C E:
			- License, documentation, and source code at: 
				https://github.com/overachiever-productions/dda/


*/


-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 0. Make sure to run the following commands in the database you wish to target for audits (i.e., not master or any other db you might currently be in).
------------------------------------------------------------------------------------------------------------------------------------------------------------------------- 


USE [your_db_here];
GO

IF DB_NAME() <> 'your_db_here' BEGIN
	-- Throw an error and TERMINATE the connection (to avoid execution in the WRONG database (master, etc.)
	RAISERROR('Please make sure you''re in your target database - i.e., change directives in Section 0 of this script.', 21, 1) WITH LOG;
END;


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
--##INCLUDE: tables\translation_keys.sql

-----------------------------------
--##INCLUDE: tables\trigger_host.sql

-----------------------------------
--##INCLUDE: tables\surrogate_keys.sql

-----------------------------------
--##INCLUDE: tables\secondary_keys.sql

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
--##INCLUDE: internal\get_engine_version.sql

-----------------------------------
--##INCLUDE: internal\split_string.sql

-----------------------------------
--##INCLUDE: internal\translate_modified_columns.sql

-----------------------------------
--##INCLUDE: internal\extract_key_columns.sql

-----------------------------------
--##INCLUDE: internal\get_json_data_type.sql

-----------------------------------
--##INCLUDE: internal\extract_custom_trigger_logic.sql


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

------------------------------------------------------------------------------------------------------------------------------------------------------
-- Utilities:
------------------------------------------------------------------------------------------------------------------------------------------------------

-----------------------------------
--##INCLUDE: utilities\list_dynamic_triggers.sql

-----------------------------------
--##INCLUDE: utilities\enable_table_auditing.sql

-----------------------------------
--##INCLUDE: utilities\enable_database_auditing.sql

-----------------------------------
--##INCLUDE: utilities\update_trigger_definitions.sql

-----------------------------------
--##INCLUDE: utilities\disable_dynamic_triggers.sql

-----------------------------------
--##INCLUDE: utilities\enable_dynamic_triggers.sql

-----------------------------------
--##INCLUDE: utilities\remove_obsolete_audit_data.sql

-----------------------------------
--##INCLUDE: utilities\set_bypass_triggers_on.sql

-----------------------------------
--##INCLUDE: utilities\set_bypass_triggers_off.sql


----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 5. Randomize bypass trigger 'key' for every environment/deployment:
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DECLARE @definition nvarchar(MAX);
SELECT @definition = [definition] FROM sys.[sql_modules] WHERE [object_id] = (SELECT [object_id] FROM sys.[triggers] WHERE [name] = N'dynamic_data_auditing_trigger_template' AND [parent_id] = OBJECT_ID('dda.trigger_host'));
DECLARE @body nvarchar(MAX) = SUBSTRING(@definition, PATINDEX(N'%FOR INSERT, UPDATE, DELETE%', @definition), LEN(@definition) - PATINDEX(N'%FOR INSERT, UPDATE, DELETE%', @definition));
SET @body = N'ALTER TRIGGER [dda].[dynamic_data_auditing_trigger_template] ON [dda].[trigger_host] '  + REPLACE(@body, N'0x999090000000000000009999', CONVERT(sysname, CAST(NEWID() AS varbinary(128)), 1));

EXEC sp_executesql @body;

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 6. Update version_history with details about current version (i.e., if we got this far, the deployment is successful). 
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DECLARE @CurrentVersion varchar(20) = N'##{{dda_version}}';
DECLARE @VersionDescription nvarchar(200) = N'##{{dda_version_summary}}';
DECLARE @InstallType nvarchar(20) = N'Install. ';

IF EXISTS (SELECT NULL FROM dda.[version_history])
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

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- 7. Notify of need to run dda.update_trigger_definitions if/as needed:
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT NULL FROM sys.[triggers] t INNER JOIN sys.[extended_properties] p ON t.[object_id] = p.[major_id] WHERE p.[name] = N'DDATrigger' AND p.[value] = 'true' AND OBJECT_NAME(t.[object_id]) <> N'dynamic_data_auditing_trigger_template') BEGIN 
	SELECT N'Deployed DDA Triggers Detected' [scan_outcome], N'Please execute dda.update_trigger_definitions.' [recommendation], N'NOTE: Set @PrintOnly = 0 on dda.update_trigger_definitions to MAKE changes. By default, it only shows WHICH changes it WOULD make.' [notes];

END;