# Dynamic Data Audits

> ### :label: **NOTE:** 
> This documentation is a work in progress. Any content [surrounded by square brackets] represents a DRAFT version of documentation.

## Overview 
Dynamic Data Audits (DDA) main benefits: 
1. **Deploy and Forget Triggers**. Stop using brittle boiler-plate triggers that make your eyeballs bleed when you code them - and NEED to be updated every, single, time you make a change to one of your audited tables. DDA tracks INSERT, UPDATE, DELETE operations dynamically - so it doesn't CARE about schema changes. 
2. **Centralized Audit Storage.** Store all of your audit data in a single table - instead of a distinct `<tableName>Audit` table per each of your audited tables (to (mostly) match the schema of your audited tables). 
3. **Optimized Search + Translation of Audit Data**. Let your END-USERs view audit data. With ALL audited changes in a single table, tracking down who did what, when, against which table is trivial. Better yet, use an optimized search routine (`dda.get_audit_data`) with pagination support, optimal performance, and the ability to TRANSLATE 'magic numbers' and other 'cruft' in your tables and/or OBFUSCATE the names of sensitive tables/columns for more sensitive data.

### Considerations
- **SQL Server 2016+ ONLY.** Relies upon NATIVE JSON support for data storage.
- **Triggers.** Uses triggers (vs CDC). Triggers are a Bad Idea(TM) when used as a 'shortcut' for implementing business logic. But they're mostly excellent for auditing purposes - except for their NORMALLY brittle nature and challenges with data-storage - both of which are addressed by dda. 

### Known Issue
- Data capture works perfectly. But there is 1 issue that can occur if/when TRANSLATIONs are defined for search/output. See the [changelog.md](/changelog.md) for more details. 


## Deployment 

### Installation
Installation involves two main steps: run `dda_latest.sql` against your target database, and then specify which tables you'd like to audit; that's it.   
  
1. **RUN [`dda_latest.sql`](https://github.com/overachiever-productions/dda/releases/latest/) in your database.** 
    - Grab the [`dda_latest.sql`](https://github.com/overachiever-productions/dda/releases/latest/) file from the [latest releases](https://github.com/overachiever-productions/dda/releases/latest/) folder.
    - Open the `dda_latest.sql` file in your favorite IDE / etc. 
        - NOTE :zap: make sure you're connected to the DATABASE where you want to deploy dda logic (i.e., that you're not in `master` or some other database where you DON'T want to deploy core dda logic).
    - Execute the `dda_latest.sql` script in its entirety. It'll create a new `dda` schema in the target/current database, wire up some tables, create a few helper sprocs/udfs, and create a trigger template and a `version_history` table. 
    - At this point, 'installation' is complete, and you're ready to move on to configuration.
    
2. **Configure: Enable Auditing against Target Tables.** 
    - NOTE: Only tables with explicit PKs or 'surrogate PKs' (defined in the `dda.surrogate_keys` table) can be audited. *'Tables' without a PK or surrogate keys aren't 'tables', they're spreadsheets - even if they live in a SQL Server database.*
    
    - See the instructions in `dda_latest.sql` for more information on how to use either `dda.enable_table_auditing` or `dda.enable_database_auditing` to 'arm' tables for auditing purposes - depending upon whether you want to audit a few tables or all/most of your tables. 
    
    - Once you've enabled auditing against one or more tables, you're done. Data will now be collected in `dda.audits` when INSERT, UPDATE, and DELETE operations are executed. 
    
    - From here, you can now search/review data using `dda.get_audit_data`
    

### Updates
[Updating DDA to the latest version of logic/functionality requires 2 steps:
1. Grab and Run/Update dda_latest.sql against your environment. This pushes latest code and logic changes into your environment. 
2. If updates to TRIGGER logic have been defined, you'll be prompted to manually update your triggers.] 

### Notes on UI Implementations
[
UI implementations facilitated by `dda.get_audit_data`.

Results/outputs of `dda.get_audit_data` are in '2 parts':
- header/meta-data - showing total-rows found/returned by input parameters (i.e., that met search criteria), current rows (pagination), operation-details (when, where, who,) and the type of operation in question (INSERT, UPDATE, or DELETE), row-counts, etc. 
- change details - i.e., JSON showing the exact nature of the changed data. Full 'rows' for INSERT/DELETE operations. Change-details for UPDATE operations.

Idea is that end-users would 'see' meta-data in a main/primary grid or display - allowing them to look through various (paginated) results 'at a glance' and then click on a specific row/result - at which point JSON details will be 'exploded' for them in another grid/display-area for them to 
'drill into' the exact changes in question.
]

## Trigger and Audit Management 

### Listing Tables with Triggers
To list all tables in your database with dda triggers configured/defined, simply run the `dda.list_dynamic_triggers` stored procedure, e.g.,: 

```sql

EXEC dda.list_dynamic_triggers;

```

### Adding Triggers to new tables or after deployment
Adding Triggers to newly created tables or to tables that you'd like to audit that weren't originally configured for auditing during 'setup/install' is easy. 

You can either re-run `dda.enable_database_auditing` to 'pickup'/add triggers to any tables you don't EXPLICITLY exclude via the `@ExcludedTables` parameter - or you can run one-off trigger additions to single, specific, tables using `dda.enable_table_auditing`. 

In both cases, the tables you wish to audit will NEED either a PK or surrogate-keys defined in `dda.surrogate_keys`.

### Cleanup of Older Records/Audit Data 
[Coming v2 or v3. A specialized sproc will help make cleanup easy and optimal (in terms of perf/concurrency).]

### Updating Trigger Logic 
[Order of Operations:
1. Push changes to the trigger 'template' against dda.trigger_host table. 
2. Use the xxx sproc to force transactionally-consistent ALTERs against all existing triggers in play within a given DB. 
3. Address any problems/errors reported by the xxx sproc with deployment IF they happen.
]

### Removing Triggers
[use SSMS (instructions) or ... execute DROP (statement/examples here).]

## Translation Management 
[NOTE TO SELF: need to add info/instructions here on how to configure/define MAPPINGs.]

[Translations are managed via: 

- `dda.translation_tables` - i.e., 'map' table names like `tb220Prefs` or `SecureTransactions` to `UserPreferences` and `Operations` (respectively) to either add context for end-users or OBFUSCATE sensitive details (respectively).

- `dda.translation_columns` - similar to table-mappings, but here you can change column-names by specifying the table + column you wish to target + the translated_name (e.g., `dbo.tb220Prefs` + `i45A` as `table` and `column` with a `translated_name` of `AlertingPerferences` would transform `dbo.tb220Prefs.i45A` to `UserPreferences.AlertingPreferences` for display purposes when combined with the table mappings listed above).

- `dda.translation_values` - similar to table and column mappings but, here, the mappings are for distinct values (magic numbers, etc.) you wish to 'cleanup' (or obfuscate) for presentation to end-users. e.g., suppose the dbo.tb220Prefs.i45A has 7 different (int) options. If one of those is, say, `1` and represents 'no alerts', rather than show end-users a `1`, you could add a mapping of `dbo.220Prefs` + `i45A` + `1` as `table`, `column`, and `value` values - along with `no_alerts` as the `translated_value` to map/transform this data for output/search.

NOTES: 
- the `[table]` column in all 3x of the translation tables listed above MUST be in `<schema_name>.<object_name>` format (i.e., `dbo.MyTable` vs just `MyTable`). 
- Stored Audit data is NEVER changed via translations. Instead, translation logic is ONLY available via 'search' sprocs (`dda.get_audit_data`, `dda.get_audit_row`) - i.e., translation is a 'presentation' level transformation only. 

]

## APIs
[
Dynamic Data Audits capabilities are made possible, primarily, via 
- a single set of trigger logic (deployed to any/all tables that need to be audited), 
- some 'helper' functions and sprocs that aid with trigger/auditing logic
- additional sprocs/code for trigger deployment, updates, and removal. 
- a set of 'helper' tables - used for translation definitions... 
- a search/query sproc - designed to optimize perf of lookups/searches AND transparently handle 'translations' - designed to make data audit/captures MORE intelligible to end-users and/or to help shield internals info if/as needed.
]

### Helper Objects 
[
- **bullet per each UDF/Sproc Name.** and high-level overview of what they do here... 
- **bullet per each UDF/Sproc Name.** and high-level overview of what they do here... 
]

### JSON Structure
Each audit-record consists of two elements: 
- **key**. Used to IDENTIFY the exact row(s) being INSERT/UPDATE/DELETE'd within the audited table.
- **detail**. Capture of the exact details that changed with the audited operation:
    - For INSERT/DELETE operations, `detail` will include the entire row (or rows) - including a 'duplicate' capture of any Primary Key data defined (e.g., if you INSERT or DELETE rows against a `dbo.Users` table where `UserID` is the Primary Key, the `UserID` value will exist in BOTH the `key` and `detail` nodes - as it BELONGS in both entities).
    - For UPDATE operations, `detail` will only capture columns changed for the row(s) modified. 

#### SYNTAX

**High-level / Root Elements:** 

SINGLE ROW SCHEMA:
```json

[{
    "key":[{   
        <key_array> }], 
    "detail":[{ 
        <detail_array>
    }]
}]

```

MULTI-ROW SCHEMA: 
```json 
[
    {
        "key":[{   
            <key_array> }], 
        "detail":[{ 
            <detail_array>
        }]
    }, 
    {
        "key":[{   
            <key_array> }], 
        "detail":[{ 
            <detail_array>
        }]
    },
    {
        "key":[{   
            <key_array> }], 
        "detail":[{ 
            <detail_array>
        }]
    }
]

```

**`<key_array>` Node:**  
The `key` node only contains key-value-pairs (i.e., column-name + value) for each column used as a Primary Key (or surrogate PK) for the table being audited.

**EXAMPLES**

A.  Single-column key example.
```json

"key": [{
    "UserID": 328
}]

```

B.  Composite Key (ParentGroupingID + ItemKey are the Primary Key columns in this table):
```json 

"key": [{
    "ParentGroupingID": 187, 
    "ItemKey": "ZZQA8-997-23A2" 
}]

```

**`<detail_array>` Node:**  
Contains either a simple list of key-value-pairs (column-name + value) for INSERT/DELETE operations, or an object showing column-names + the `from` (before) and `to` (after) values for changes captured during `UPDATE` operations.

**EXAMPLES**   

A. Sample entry for an INSERT or DELETE:

```json

	"detail": [{
		"email_address":"sheila.jones@big-corp.corp",
		"first_name":"Sheila",
		"last_name": "Jones", 
		... etc. 
	}]

```

B. Sample entry for an UPDATE - where each modified column contains `from` and `to` elements to enable before and after tracking:  

```json

	"detail": [{
		"InventoryCount": [{
			"from": 182, 
			"to": 77
		}], 
		"ModifiedDate": {
			"from":"2021-01-08", 
			"to":"2021-01-22"
		}

	}]


```

#### Full Examples
The following examples represent full / complete JSON 'documents' - i.e., examples of what Dynamic Data Audit Triggers can and will 'capture' for auditing purposes and long-term storage. 

A. Example of an INSERT for a new User - Sheila Jones (NOTE that her UserID (328) is captured as both the `key` and as part of the `detail` as well - which is by design):

```json 

[{
    
    "key": [{
        "UserID": 328
    }], 
    
	"detail": [{
	    "UserID": 328,  
	    "email_address":"sheila.jones@big-corp.corp",
	    "first_name":"Sheila",
	    "last_name": "Jones",
	    "etc":"more info here... "
	}]    
    
}]


```


B. Example of an UPDATE - where the item/inventory-count for a specific product was decremented: 

```json 

[{
    "key": [{
        "ParentGroupingID": 187, 
        "ItemKey": "ZZQA8-997-23A2" 
    }], 
    
	"detail": [{
		"InventoryCount": {
			"from": 182, 
			"to": 77
		}, 
		"ModifiedDate": {
			"from":"2021-01-08", 
			"to":"2021-01-22"
		}

	}]    
}]


```