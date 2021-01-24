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
Each row/entry captured by Dynamic Data Audit Triggers will adhere to the following JSON structure. 

At a high-level, each audit record consists of two elements/nodes:  
- **key** - which contains 'identifying' information about the row being audited (i.e., either the primary key column(s) or defined surrogate key(s)/column(s)).
- **detail** - which contains capture-info of the exact columns changed or `INSERT/DELETE`'d. For `INSERT/DELETE` operations, the `details` node will only contain a simple array of key-value-pairs - for the column-names and data `INSERT/DELETE`'d. For `UPDATE` operations, the `details` node will contain a set of arrays - in the form of `column-name-modified` + `from`, to `values` such that each `UPDATE` 'capture' will display the before and after values for each column modified during the `UPDATE`.


#### SYNTAX

**High-level / Root Elements:** 

```json

[{
    "key":[{   
        <key_array> }], 
    "detail":[{ 
        <detail_array>
    }]
}]

```


**`<key_array>` Elements:**  
Will only ever contain a list of scalar entries/values. 

Fully specified (i.e., including root/parent node) examples: 

A.  Single-column key example.
```json

"key": [{
    "UserID": 328
}]

```

B.  Example from a table with a composite key (ParentGroupingID + ItemKey are the Primary Key columns in this table):
```json 

"key": [{
    "ParentGroupingID": 187, 
    "ItemKey": "ZZQA8-997-23A2" 
}]
```


`<detail_array>` Elements:  
Can contain an array of scalar elements (for `INSERT/DELETE` operations).  
Can also contain an array of multi-node values - when storing data for `UPDATE` operations. 

A. Sample entry for INSERT or DELETE details - scalar values only:

```json

	"detail": [{
		"email_address":"sheila.jones@big-corp.corp",
		"first_name":"Sheila",
		"last_name": "Jones", 
		... etc. 
	}]

```

B. UPDATE variant - each modified column contains 2 child-elements showing `from` and `to` elements (i.e., before and after values) from the change: 

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
		... etc. 
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