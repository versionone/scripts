# Removing redundant history records from your VersionOne database

## Quick Start

**Note:** These steps should be done when the database is not otherwise in use.
Stop the Lifecycle application, or put the database in SINGLE USER mode.

### Removing Redundancy
To remove any redundant history in your VersionOne database, run these scripts **in this order**:

1. remove_LongString_redundancy_new
	- _Edit the start of this script to set @saveChanges = 1_
2. remove-redundant-access-history
	- _Edit the start of this script to set @saveChanges = 1_
3. remove-redundant-asset-history
	- _Edit the start of this script to set @saveChanges = 1_
4. remove-custom-relation-redundancy
	- _Edit the end of this script to COMMIT instead of ROLLBACK_
5. remove-redundant-custom-history
	- _Edit the end of this script to COMMIT instead of ROLLBACK_
6. remove-redundant-commit-activity-activitystream-history
	- _Edit the start of this script to set @saveChanges = 1_

### Verifying Historical Integrity
To identify problems in history, run these scripts:

1. check-history-coherency
1. check-history-vs-now

### Fixing Historical Integrity
To fix problems in history, run this script:

1. stitch
	- _Edit the start of this script to set @histTable = an asset name_
	- _Edit the start of this script to set @saveChanges = 1_


## Details: Removing Redundancy

### LongString records
The `LongString` table stores text blob values for Long Text attibues of various assets. Repeatedly updating a Long Text attibute on an asset with the same value results in a new text blob being saved for that value each time, leading to asset history redundancy. To detect and remove this redundant asset history, existing text blob references to duplicate values need to be remaped to point to same unique blob values.

### remove_LongString_redundancy_new.sql
This script removes duplicate entries from the `LongString` table, and remaps references to these duplicates across all Long Text attributes to point to the remaining unique values.

By default, this script **will not commit** its changes; to save changes, edit the _start_ of the script, uncommenting the `set @saveChanges = 1` statement.


### Access Records
The `Access` table records when each user accesses VersionOne, at most once per day.  If an integration does not send cookies in its API calls, it is possible for multiple accesses per day to be recorded.

#### remove-redundant-access-history.sql
This script removes duplication from the `Access` table.  Its output shows the number of actual records deleted.

By default, this script **will not commit** its changes; to save changes, edit the _start_ of the script, uncommenting the `set @saveChanges = 1` statement.


### Assets
Saving assets multiples times without actual data changes can cause them to accumulate redundant historical records.  This might occur, for example, with an integration that invokes the API to save assets that have not changed.

#### remove-redundant-asset-history.sql
This script removes duplication from every asset table.  Its output shows the number of actual records deleted.

By default, this script **will not commit** its changes; to save changes, edit the _start_ of the script, uncommenting the `set @saveChanges = 1` statement.


### Custom Attributes
Custom attributes are stored separately from their assets, and can accumulate their own historical redundancy. Two scripts remove this redundancy:

#### remove-custom-relation-redundancy.sql
This script removes duplication from the `CustomRelation` table. Its output shows the amount of redundancy before and after.

By default, this script **will not commit** its changes; to save changes, edit the _end_ of the script to commit, instead of rollback.

#### remove-redundant-custom-history.sql
This script removes duplication from the `CustomBoolean`, `CustomDate`, `CustomLongText`, `CustomNumeric`, and `CustomText` tables.  Its output shows the amount of redundancy before and after. It follows up by rebuilding the `AssetAudit` table, which is ultimately required after any modifications to history.

By default, this script **will not commit** its changes; to save changes, edit the _end_ of the script to commit, instead of rollback.

### Commits, Activity, and Activity Stream
Updating an Asset without actual changes can cause historical records in the Commits, Activity, and ActivityStream tables. This script will delete the Commit records where the Payload contains no changes, and then take each of these deleted commit's `CommitId` and delete any Activity records with a Body containing this `CommitId`. Associated ActivityStream records are also deleted.

By default, this script **will not commit** its changes; to save changes, edit the _end_ of the script to commit, instead of rollback.



## Details: Checking Historical Integrity
These scripts do not modify the database in any way, but check for possible problems in the historical records.  VersionOne Support may ask you to run these as a diagnostic tool.

Any problems identified by these scripts can be fixed by running the __stitch.sql__ script.

#### check-history-coherency.sql
This script verifies that historical records are correctly sequenced.  Any problems found will be detailed in its output.

#### check-history-vs-now.sql
This script verifies that the _current_ records match the _last_ historical records.  Any problems found will be detailed in its output.



## Details: Fixing Historical Integrity
#### stitch.sql
This script fixes the sequenceing of historical records, and matches _current_ records to the _last_ historical records.

To use this script, it must be edited to specify exactly _which_ asset's history to fix (as identified by one of the _check-history_ scripts).  Edit the _start_ of the script to `set @histTable` variable to the name of the problematic asset.

Additionally, by default, this script **will not commit** its changes; to save changes, edit the _start_ of the script, uncommenting the `set @saveChanges = 1` statement.
