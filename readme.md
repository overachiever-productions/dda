# Dynamic Data Audits
## Overview 
Dynamic Data Audits (DDA) provide two main benefits: 
1. Deploy and Forget triggers that dynamically capture INSERT, UPDATE, DELETE details without requiring developers to [create boilerplate-ish triggers] or 'touch'/ALTER trigger definitions any time schema of the underlying table is changed (i.e., add/remove or rename a column? no biggie, DDA Triggers don't care, they'll keep working without need of updates).
2. Option to easily define translations that [xyz...designed to make data audit/captures MORE intelligible to end-users and/or to help shield internals info if/as needed.] ]

### Benefits
- Easy - deploy once - vs constant-touch/update.
- Light-weight overhead + fast. 
- UPDATEs only track changed columns - vs all columns
- Securable. distinct schema to help with management of access/perms.

### Considerations
- Capture/Storage is SQL Server 2016+ ONLY - due to reliance upon NATIVE JSON capabilities.
- Querying/Review/Output is SQL Server 2017+ ONLY - due to reliance upon STRING_AGG() function.
- Triggers. Normally not good - but optimal for data-audit capabilities. 

### Known Issues 
- ... 
- ... 
- ... 


## Deployment 

[create a section for each of the following bullet-points]
- [how to download/run/install scripts.]
- [how to list tables without explicit PKs]
- [How to add PKs to tables without PKs]
- [how to define surrogates for PKs that don't have PKs and creating PKs may not be ideal (yet)]
- [how to deploy audit triggers - per table, or against all tables (minus @Exclusions)]

- [how to query/view captured data (raw view)]
- [How to 'search' via the get_audit_data sproc... ]


### Notes on UI stuff
[notes about 2-phase/split display - i.e., 'header' info (non-JSON results from dda.get_audit_data) + click-on/activate-view of 'detail' info (JSON data) per user-interaction... etc.]

## Trigger and Audit/Capture Management 

### Listing Tables with Triggers
[sproc/view]

### Adding Triggers to new tables or after deployment
[blah]

### Cleanup of Older Records/Audit Data 
[Sproc to help manage cleanup. Best option is to schedule a nightly/weekly job... ]

### Updating Trigger Logic 
[Order of Operations:
1. Push changes to the trigger 'template' against dda.trigger_host table. 
2. Use the xxx sproc to force transactionally-consistent ALTERs against all existing triggers in play within a given DB. 
3. Address any problems/errors reported by the xxx sproc with deployment IF they happen.
]

### Removing Triggers
[use SSMS (instructions) or ... execute DROP (statement/examples here).]

## Translation Management 
[overview of translation processes/schema - with examples, etc.]

## APIs
Dynamic Data Audits capabilities are made possible, primarily, via 
- a single set of trigger logic (deployed to any/all tables that need to be audited), 
- some 'helper' functions and sprocs that aid with trigger/auditing logic
- additional sprocs/code for trigger deployment, updates, and removal. 
- a set of 'helper' tables - used for translation definitions... 
- a search/query sproc - designed to optimize perf of lookups/searches AND transparently handle 'translations' - designed to make data audit/captures MORE intelligible to end-users and/or to help shield internals info if/as needed.

### Helper Objects 
- **bullet per each UDF/Sproc Name.** and high-level overview of what they do here... 
- **bullet per each UDF/Sproc Name.** and high-level overview of what they do here... 
- **bullet per each UDF/Sproc Name.** and high-level overview of what they do here... 
- **bullet per each UDF/Sproc Name.** and high-level overview of what they do here... 

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