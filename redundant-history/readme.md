# Removing redundant history records from your VersionOne database

## Quick Start
Run the scripts in this folder in this order:

1. remove-redundant-access-history
	- _Edit the start of this script to set @saveChanges = 1_
2. remove-redundant-asset-history
	- _Edit the start of this script to set @saveChanges = 1_
3. remove-custom-relation-redundancy
	- _Edit the end of this script to COMMIT instead of ROLLBACK_
4. remove-redundant-custom-history
	- _Edit the end of this script to COMMIT instead of ROLLBACK_


## Details
### Access Records
The `Access` table records when each user accesses VersionOne, at most once per day.  If an integration does not send cookies in its API calls, it is possible for multiple accesses per day to be recorded.

#### remove-redundant-access-history.sql
This script removes duplication from the `Access` table.  Its output shows the number of actual records deleted.

By default, this script **will not commit** its changes; to save changes, edit the _start_ of the script, uncommenting the `set @saveChanges = 1` statement.


### Assets
Saving assets multiples times without actual data changes can cause them to accumulate redundundant historical records.  This might occur, for example, with an integration that invokes the API to save assets that have not changed.

#### remove-redundant-asset-history.sql
This script removes duplication from every asset table.  Its output shows the number of actual records deleted.

By default, this script **will not commit** its changes; to save changes, edit the _start_ of the script, uncommenting the `set @saveChanges = 1` statement.


### Custom Attributes
Custom attributes are stored separately from their assets, and can accumulate their own historical redundancy. Two scripts remove this redundancy:

#### remove-custom-relation-redundancy.sql
This script removes duplication from the `CustomRelation` table. Its output shows the amount of redundency before and after.

By default, this script **will not commit** its changes; to save changes, edit the _end_ of the script to commit, instead of rollback.

#### remove-redundant-custom-history.sql
This script removes duplication from the `CustomBoolean`, `CustomDate`, `CustomLongText`, `CustomNumeric`, and `CustomText` tables.  Its output shows the amount of redundency before and after. It follows up by rebuilding the `AssetAudit` table, which is ultimately required after any modifications to history.

By default, this script **will not commit** its changes; to save changes, edit the _end_ of the script to commit, instead of rollback.



