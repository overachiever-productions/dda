# Change Log

## [0.8] - 2021-01-23

### Initial Check-in
Initial check-in to a new/stand-alone repository. 

### Known-Issues:
- Early Build / Initial Beta. 
- JSON output from `dda.get_audit_data` is not fully/well formed - especially for translations (i.e., current release is a proof of concept that captures/displays and TRANSFORMS JSON, but the syntax output has NOT been standardized against syntax definitions specified in readme.md).
- MULTI-ROW audits/captures are not supported via `dbo.get_audit_data` - e.g, an `UPDATE` that modifies, say, 7 rows (instead of 1), will be CAPTURED into `dda.audits` with the details for all 7x rows, but `dda.get_audit_data` will NOT account for these (and may even break). 