# Removing redundant history records from your VersionOne database

## Quick Start
To remove any rundandant history in your VersionOne database, run these scripts in this order:

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



## Checking Historical Integrity
These scripts do not modify the database in any way, but check for possible problems in the historical records.  VersionOne Support may ask you to run these as a diagnostic tool.

Any problems identified by these scripts can be fixed by running the __stitch.sql__ script.

#### check-history-coherency.sql
This script verifies that historical records are correctly sequenced.  Any problems found will be detailed in its output.

#### check-history-vs-now.sql
This script verifies that the _current_ records match the _last_ historical records.  Any problems found will be detailed in its output.



## Fixing Historical Integrity
#### stitch.sql
This script fixes the sequenceing of historical records, and matches _current_ records to the _last_ historical records.

To use this script, it must be edited to specify exactly _which_ asset's history to fix (as identified by one of the _check-history_ scripts).  Edit the _start_ of the script to `set @histTable` variable to the name of the problematic asset.

Additionally, by default, this script **will not commit** its changes; to save changes, edit the _start_ of the script, uncommenting the `set @saveChanges = 1` statement.

