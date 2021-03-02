[DDA Docs Home](/readme.md) > [DDA APIs](/documentation/apis.md) > `dda.get_audit_data`

# dda.get_audit_data

## Table of Contents
- [Overview](#overview)
- [Syntax](#syntax)
- [Remarks](#remarks) 
- [Examples](#examples)
- [See Also](#see-also)

## Overview
**APPLIES TO:** :heavy_check_mark: SQL Server 2016+ 

## Syntax

```

    dda.get_audit_data [ @objname = ] 'name' [ , [ @columnname = ] computed_column_name ]  

```

### Arguments
`[ @objname = ] 'name'`
 Is the qualified or nonqualified name of a user-defined, schema-scoped object. Quotation marks are required only if a qualified object is specified. If a fully qualified name, including a database name, is provided, the database name must be the name of the current database. The object must be in the current database. *name* is **nvarchar(776)**, with no default.  
  
`[ @columnname = ] 'computed_column_name'`
 Is the name of the computed column for which to display definition information. The table that contains the column must be specified as *name*. *column_name* is **sysname**, with no default.  
 
 [Return to Table of Contents](#table-of-contents)
 
 ### Return Code Values 
  0 (success) or non-0 (failure)  
  
 ## Result Sets  
 
|Column name|Data type|Description|    
| :-------- | :-------|:----------------------  |
|session_id|**smallint**|ID of the session to which this request is related. Is not nullable.| 
|request_id|**int**|ID of the request. Unique in the context of the session. Is not nullable.|  

[Return to Table of Contents](#table-of-contents)

## Remarks

[Business Rules for Inputs/Parameters: 

- `@StartTime` can be specified without `@EndTime` (in which case, `@EndTime` will be defaulted to 'now' or `GETDATE()`). 
- However, `@EndTime` can NOT be specified without `@StartTime`.
- Both `@StartTime` and `@EndTime` can be empty/NULL IF either `@TargetUsers` or `@TargetTables` have been specified. 
- Or, in other words, both `@TargetTable` or `@TargetUser` can be queried WITHOUT specifying times. 

*In short: there ALWAYS has to be at LEAST 1x WHERE clause/predicate - but more are always welcome.*

]


[Return to Table of Contents](#table-of-contents)

## Permissions 


## Examples

### A. Doing such and such
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
```sql

SELECT 'example stuff here';

```

### B. Doing blah blah

Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
```sql

SELECT 'example stuff here';

```
Lacus vel facilisis volutpat est. Molestie a iaculis at erat pellentesque adipiscing. Non quam lacus suspendisse faucibus.


[Return to Table of Contents](#table-of-contents)

## See Also
- [best practices for such and such]()
- [related code/functionality]()

[Return to Table of Contents](#table-of-contents)

[S4 Docs Home](/readme.md) > [S4 APIs](/documentation/apis.md) > dda.get_audit_data