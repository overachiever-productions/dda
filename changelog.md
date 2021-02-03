# Change Log

## [1.0] - xxx
Fully Functional - Initial Release. 

### Known Issues: 

## Fixed:
- Corrected bug with v0.9 Bug with `from` and `to` translations of non-string data-types (i.e., no longer wrapping all JSON values with 'extra' quote (`) characters).
- INSERT/UPDATE/DELETE operations that impact > 1 row now correctly serialize audit/capture details down to (schema compliant) multi-row JSON. 
- `dda.get_audit_data` now correctly handles/translates multi-row JSON audit entries (i.e., INSERT/UPDATE/DELETE operations that impact > 1 row can now be correctly output + translated).

## Added
- 

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