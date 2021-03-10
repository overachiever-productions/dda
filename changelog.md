# Change Log

## [3.0] - 2021-03-09
Translations via Foreign Key Mappings + JSON formatting fixes + search improvements.

## Known-Issues: :zap:
- `dda.get_audit_data` with `@TransformOutput = 1` on SQL Server 2016 instances with `MUTATE`/`"dump"` captures breaks JSON output/formatting (returns an 'empty array' - e.g., `[]`). This will be fixed with an intermediate release - v3.2 in a few days. 

## Added
- `dda.translation_keys` - new table that allows 'mapping' of Foreign Keys for transformation/translation of JSON output via `dda.get_audit_data`. For example, if you have a table called `dbo.user_preferences` with a column called `alerting_preference` that points to a 'lookup' table called, say, `dbo.alerting_options` with an `alerting_option_id` (1, 2, 3, 4, and so on) and corresponding values of, say, 'email', 'sms', 'push', 'none', etc... then while audits will capture a change from, say, `1` to `3` against `dbo.user_preferences.alerting_preference` when a user switches their preference from email to push... but that won't help a ton if/when looking at audit-data later on - unless you've got 'carnal' knowledge of what a 1 or 3 is, etc. With `dda.translation_keys` you can now instruct `dda.get_audit_data` to use a logical foreign key (it can be explicit or implied) by specifying that `table_name = 'dbo.user_preferences'` and `column_name = 'alerting_preference'` 'points' to `key_table = 'dbo.alerting_options'` with a 'key' (lookup) column of `key_column = 'alerting_preference_id'` with display/output values from `'value_column = 'preference_name'` - at which point translations will be handled just as expected from a FK lookup-table.

- Ability to BYPASS Triggers for maintenance purposes. Installation/Updates of `dda_latest.sql` will create a unique (`NEWID()`) value that if/when found in `CONTEXT_INFO()` of any operations hitting/touching audited tables, will cause a short-circuit of trigger logic and BYPASS normal trigger/audit processing. 
To see what the 'key' is for your database (this 'key' will be different per each instance/deployment of DDA), 'modify' an existing DDA trigger on one of your target tables and look for the code that says `IF @context = 0x000ValuesHere000##`. Then, if for example, your 'key' or `@context` value was, say, `0x910E7779ECEC9D4585055F2BF1091F51` you could run the following code: 

```sql 

SET CONTEXT_INFO 0x910E7779ECEC9D4585055F2BF1091F51;

```
and then if/when you make subsequent changes within the currently loaded/configured session (i.e., disconnect or explicitly change your CONTEXT_INFO() and this 'bypass ability' will obviously 'go away'), you won't 'trigger' audit captures or other processing/logic against any DDA audited tables. (Helpful for if/when you need to push, say, a software update/patch that changes a table with 10K columns from allowing NULLs for column xyz to a new default value of `'some value here'` - because, otherwise, your options are to either a. kick out all users/apps and quiesce the database or b. run the risk that while you run this UPDATE someone 'sneaks' in a 'legit' change while the DDA trigger has been temporarily disabled for your 10K row 'update'.)

- `dda.get_audit_data` can now be queried by either a single `AuditID` value, a RANGE of `@StartAuditID` to `@EndAuditID` values or by similar options for `@StartTransactionID` through `@EndTransactionID`. In either case, IF you only specify the `@StartXXXXID` with no `@EndXXXID`, then only a single ID will be fetched (if it exists). Likewise, for TransactionID lookups, you can specify actual `int` values directly from the `dda.audits.transaction_id` table (along with an optional `@TransactionDate` parameter to avoid duplicates) OR you can use 'formatted' TransactionIDs as returned from `dda.get_audit_data` in the form of `yyyy-doy-#####` (where doy = day of year, and ### represents the integer transaction_id).

## Fixed 
- Known issue from versions 1 and 2 with translations of JSON data (from say, a literal value of `2` to `"email"`) no longer runs the risk of breaking JSON output when `@TransformOutput = 1` from `dda.get_audit_data` - i.e., data-types for translated/non-translated data are correctly handled.

## [2.0] - 2021-03-01 
Minor Bug-Fixes + Multi-Row Key-Change Capture Improvements.

## Known-Issues: :zap: 
1. Issue from version 1.3 with translation mappings that can 'break' JSON 'data-types' remains - and will be fixed in v3.0. 

## Added 
- Addition of new `ROTATE` capture - i.e., 1st-class capture/audit record on par with `INSERT`, `UPDATE`, and `DELETE` where a `ROTATE` is simply an `UPDATE` where NO data (at ALL) was logically changed (e.g., `UPDATE dbo.Users SET FirstName = 'Mike' WHERE FirstName = 'Mike';` can/will 'update' any rows where the `FirstName` value was `'Mike'`, but this 'update' didn't truly change any data and was just 'spinning its wheels' - and will be listed in dda.audits.operation as a `'ROTATE'`). RATIONALE: A `ROTATE` can be easily excluded from search and/or regularly deleted from dda.audits via cleanup logic - but the CAPTURE of `ROTATE` operations allows admins/devs to identify 'useless'/non-optimal operations that might be causing excessive 'changes' when NO REAL changes are occuring.

- `dda.secondary_keys` - table that allows for addition of secondary-keys (i.e., surrogate keys for tables with PKs) to enable row-by-row capture of modifications to Primary Key Columns for MULTI-ROW UPDATES (e.g., assume a PK exists with `JobID` and `StepID` as a compound key - and an UPDATE changes all `StepID` values in said table for `JobID` = 337 to `StepID = StepID + 25`; at this point, N number of rows have had their PK changed - and there is EITHER a surrogate/secondary key defined that'll let us track these changes row-by-row (between `DELETED` and `INSERTED`) or ... a `"dump"` will occur).     

***NOTE:** dump operations will be marked as a `MUTATE` in the `dda.audits.operation` column - to make operations with a non-trackable set of PK modifications easier to spot.*  

- Addition of `"dump"` node in JSON for scenarios where a) MULTI-ROW UPDATEs are fired, b) Primary Key columns (1 or more) have been MODIFIED, c) there's no dda.secondary_key mapping defined. NOTE: single-row changes to PKs columns and multi-row INSERT/DELETE operations (involving PK columns) are not subject to needing secondary keys or being dumped.   
  
***NOTE:** a "dump" is full output from the `DELETED` and `INSERTED` pseudo-tables from within the dynamic data auditing trigger - and a future version of DDA will provide some options for POST-DUMP mapping/remapping to remove "dumps" by enable re-processing of secondary keys. Otherwise, if/when MULTIPLE rows have their PK values changed (and there's no secondary mapping) it's currently impossible to be 100% certain of which rows in `DELETED` correspond to which rows in `INSERTED` - hence the `"dump"`. (A future version MAY look at hashing and/or evaluating non-modified columns during a `MUTATE` operation to attempt to 'glue' `DELETED` and `INSERTED` rows back together when this can be done with 100% certainty and without causing significant perf overhead.)*

- `dda.list_dynamic_triggers` now shows version information about the DDA version for each dynamic trigger deployed. Likewise, executing `dda.update_dynamic_triggers` reports on version changes. 

- Rough-in/Stub for API documentation added. (Not yet ready for 'publication' - but placeholders now exist in project structure/code-base.)

- Initial addition of tSQLt Unit Tests have been 'stubbed' into project structure.

## Fixed
- Miscellaneous/Minor fixes to address potential problems with "string or binary data would be truncated errors", knock dda.audits.operation (type) column down to char(6) vs char(9).


## [1.3] - 2021-02-15
Bug-Fixes + Improvements to core functionality.

## Known Issue: :zap:
1. Translations/mappings can inadvertently bust/break JSON data-typing. For example, assume you have a `dbo.UserPreferencesTable` with an `NewItemAlerts` (preferences) column - containing 'magic numbers' or ints (where, say, `0 = no alert`, `1 = email-alerts-only`, `2 = push-alerts`, `3 = sms-alerts`, and so on). CAPTURE or auditing of changes to this column will use CORRECT JSON - i.e., 'numerical' JSON in the form of, say, `"NewItemAlerts":3`, but - translations can cause this 'typing' to break - when swapping out 'magic numbers' for text. For example, if you created an explicit mapping in dda.translation_values that mapped the value `3` to the literal text `SMS or Text` this CAN (but will not ALWAYS) 'bust' JSON outputs during translation such that you might see something like `"NewItemAlerts":SMS or Text` - which is incorrect (it should be `"NewItemAlerts":"SMS or Text`" instead - i.e., text should be "wrapped"). Note that v2.0 will provide support for 'foreign key' mappings (vs the one-off(ish) mappings in `dda.translation_values`) and will also, as a consequence fix/correct this known bug. 

## Added: 
- `dda.get_audit_data` now includes a `transaction_id` column in output (to help spot 'linked' operations via TX IDs).

## Fixed
**Translation Fixes:**
- A Major Bug (unknown issue at time of v1.0 publication) with translation attempts to pre-optimize outputs (against non-translated outputs) removing ALL output/translation data in `dda.get_audit_data` corrected. 
- Translation + NULLs. A known issue in v1.0 would result in `UPDATE`s involving `NULL` values in the `from`/`to` JSON to skip/bypass translations or explicit translation mappings. This has been corrected in v1.3.
- Known-issue in version 1.0 where 'column order' within translated JSON outputs COULD shift or change order (e.g., if `INSERT`ed columns were `UserName`, `UserEmail`, and `UserPreferences` in audited/captured JSON, the existence of mappings/translations MIGHT cause translated JSON to output in `UserPreferences`, `UserName`, `UserEmail` (or other 'changed' orders)) - has been fixed in v1.3.

**Other Fixes:**
- `dda.version_history` now correctly distinguishes between INSTALL and UPDATE deployments. 
- `dda.audits.operation` column was incorrectly set to `char(9)` vs `char(6)` - now corrected during INSTALL/UPDATEs.

## [1.0] - 2021-02-09
Fully Functional - Initial Release. 

### Known Issues: :zap:
- Translation + JSON Column-Order. In SOME cases the presence of a translation (via `dda.translation_columns` or `dda.translation_values`) MAY result in scenarios where column orders (either in the `"key"` or `"detail"` section (or both)) MAY be changed/reversed. e.g., if captured JSON was `[{ "key": [{ "UserPreferenceID":185}], "detail": [{ "UpdatePreference": 12, "AlertingPreference": 7 }] }]` it IS possible that a translation on/against - say, `"AlertingPreference of 7 => 'email_and_push'"` could/would (in some cases) result in the `AlertingPreference` and `UpdatePreference` 'column order' within JSON to deviate and/or change from what was in the original 'capture'. 
- Translation + JSON Data-Types. Similarly, ih the example above, the 'translation' from the 'magic number' value of `7` for an `AlertingPreference` to `email_and_push` (a text value - instead of a numeric value), can/frequently-will result in mal-formed JSON in the form of `...,"AlertingPreference":email_and_push` (vs what should, correctly, be rendered in JSON as `..., "AlertingPreference":"email_and_push"...`).
- Translation + NULLs. Translation mappings for values to/from NULL (via UPDATEs) are currently being skipped or missed during translation. 

> ### :label: **NOTE:** 
> *All, above, known-issues are problems with translation/output only (i.e., capture and storage of JSON is working correctly, but 'search' or 'review' operations involving the 3x scenarios above can/will result in known problems.)*

## Fixed:
- Dynamic Data Triggers now correctly CAPTURE `NULL` values in INSERT, UPDATE, and DELETE operations. (Previously they were simply skipped/missing.)
- `dda.get_audit_data` now works on SQL Server 2016 instances. Previously, it only worked on SQL Server 2017+ instances (because of reliance upon `STRING_AGG()` for concatenation). Deployment now pushes XML-concat version (2016 compatible) as default implementation, and runs an ALTER (update) to use (faster) `STRING_AGG()` on 2017+ instances.
- INSERT/UPDATE/DELETE operations that impact > 1 row now correctly serialize audit/capture details down to (schema compliant) multi-row JSON. 
- `dda.get_audit_data` now correctly handles/translates multi-row JSON audit entries (i.e., INSERT/UPDATE/DELETE operations that impact > 1 row can now be correctly output + translated).
- Corrected bug with v0.9 Bug with `from` and `to` translations of non-string data-types (i.e., no longer wrapping all JSON values with 'extra' quote (`) characters).

## Added:
- `dda.enable_database_auditing` - Admin/Utility sproc to enable auditing of entire database - minus/excluding any tables without PKs (either by explicit exclusion `@ExcludedTables` or by 'skipping' all tables without explicit PKs - `@ExcludeTablesWithoutPKs`). Note that `dda.enable_database_auditing` will provide detailed summary/output information about which tables were 'added' to auditing, which could NOT be added (explicit or 'skipped' exclusions), those that already HAVE auditing triggers (but that need to be updated), and any errors/exceptions encountered along the way. In short, `dda.enable_database_auditing` is now 'step 2' in deploying auditing capabilites - i.e., install/deploy scripts, then run this 'command'. 
- `dda.get_engine_version` - Internal/helper routine to help with conditional builds/deployment (specifically `STRING_AGG()` update (ALTER) for 2017+ instances to allow faster execution for `dda.get_audit_data`).

## [0.9] - 2021-01-23
Core Functionality Complete and JSON is schema-compliant.

### Known Issues: :zap:
- Multi-Row INSERT, UPDATE, DELETE operations are NOT supported, currently, via transforms (or possibly AT ALL) for output/search - i.e., running `dda.get_audit_data` against matches with `[row_count]` > 1 in `dda.audits` a) won't transform, and b) may simply break sproc/outputs entirely. 

> ### :label: **NOTE:** 
> Multi-Row INSERT, UPDATE, DELETE operations ARE captured correctly(ish) as JSON via dynamic data triggers. (-ish means that I need to review/revisit if I LIKE the existing schema - may make some minor (or major) changes to multi-row captures.)

- JSON 'data types' are lost/mangled for `from` - `to` changes during translations. (They may also? be lost/mangled for 'scalar' translations too (i.e., during INSERT/DELETE operations instead of JUST during UPDATEs)). For example, assume that the column `[total_cost]` is `UPDATE`'d from `120.00` to `191.12`. The from/to JSON for this should be rendered as: ` { "from":120.00, "to":191.12}` but will currently render as ` { "from":"120.00", "to":"191.12" }` - i.e., with extra 'quotes' (`"`) around the numerical values that, technically, shouldn't be there. 

## Fixed
- INSERT, DELETE, and UPDATE operations captured by the dynamic data trigger ALL comply with the JSON schema defined in readme.md's JSON SYNTAX documentation (i.e., key + detail nodes + underlying child nodes if/as needed).
- `dda.get_audit_data` now, also, emits schema-defined JSON as well. 

## Added
- `@TransformOutput` Parameter added to `dda.get_audit_data`. Defaults to `1` (transform output), but can, explicitly, be set to 0 - to allow users/devs/techs/etc. to troubleshoot and audit data 'internally' without having to worry about odd/goofy transforms that might 'obfuscate' details.
- `dda.list_deployed_triggers` - Logic to list all deployed dynamic data triggers in-play within database.
- `dda.update_trigger_definitions` - Script to force/update all existing (deployed) triggers within a given database to the latest version of the trigger definition defined on/against `dda.trigger_host` (usefull (currently) for bug fixes/tuning and so on - i.e., make changes to the 'template definition - then execute `dda.update_trigger_definitions @PrintOnly = 0;`).
- Triggers (bletch) against translation tables to help enforce business rules relative to table names (i.e., `<schema>.<table>` vs 'just-table-name') and warn on non-matched translations (translations defined without corresponding tables/tables+column-names).


## [0.8] - 2021-01-23  

### Initial Check-in
Initial check-in to a new/stand-alone repository. 

### Known-Issues: :zap:
- Early Build / Initial Beta. 
- JSON output from `dda.get_audit_data` is not fully/well formed - especially for translations (i.e., current release is a proof of concept that captures/displays and TRANSFORMS JSON, but the syntax output has NOT been standardized against syntax definitions specified in readme.md).
- MULTI-ROW audits/captures are not supported via `dbo.get_audit_data` - e.g, an `UPDATE` that modifies, say, 7 rows (instead of 1), will be CAPTURED into `dda.audits` with the details for all 7x rows, but `dda.get_audit_data` will NOT account for these (and may even break). 