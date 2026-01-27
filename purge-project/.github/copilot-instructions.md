# Copilot Instructions for PurgeProject Scripts

## Purpose
These SQL scripts purge (delete) an entire project and all its related data from a VersionOne database. Each script is version-specific and must match the database schema for that version.

## File Naming Convention
- `PurgeProject-{major}.{minor}.sql` - One script per version
- Version check enforced: Scripts validate they run on correct database version
- Point releases (e.g., 25.0, 25.1, 25.2, 25.3) track MAJOR.MINOR versions only

## Script Structure (Three Phases)

### Phase 1: "Rack 'em" (Lines ~50-400)
**Purpose:** Identify what to delete (doom) and what to preserve (safe)

**Tables:**
```sql
@doomed - IDs to be deleted
@safeScopes - Scopes to preserve
@safeMembers - Members to preserve  
@safeTeams - Teams to preserve
```

**Pattern:**
1. Doom the target Scope and its children recursively
2. Doom entities that belong to doomed Scopes
3. Mark safe: entities used by safe (non-doomed) Scopes
4. Doom only entities not in safe lists

### Phase 2: "Stack 'em" (Lines ~500-1400)
**Purpose:** Delete doomed entities in proper dependency order

**Pattern:**
- Delete junction tables first (many-to-many)
- Delete child entities before parents
- NULL out foreign keys before deleting
- Handle both `_Now` views and history tables

### Phase 3: Rebuild (Lines ~1500+)
**Purpose:** Rebuild denormalized data structures
```sql
-- Rebuild EffectiveACLs
insert dbo.EffectiveACL ...
```

## Entity Classification

### First-Party Entities (Owned by Scope - GET DOOMED)
**Pattern:** `doom [Entity] that live in doomed Scopes`
```sql
insert @doomed
select ID from Entity_Now join @doomed on doomed=ScopeID
```
**Examples:** Goal, Roadmap, Issue, Request, Workitem, Scope itself

**Deletion pattern:**
```sql
raiserror('Goals', 0, 1) with nowait
delete JunctionTable from @doomed where doomed=GoalID
delete Goal_Now from @doomed where doomed=ID
update Goal_Now set TeamID=null from @doomed where doomed=TeamID
delete Goal from @doomed where doomed=ID
update Goal set TeamID=null from @doomed where doomed=TeamID
raiserror('%s Goals purged', 0, 1, @rowcount) with nowait
```

### Second-Party Entities (Selective Purging - TRACK SAFE)
**Pattern:** Track safe entities, doom only unsafe ones
```sql
-- Mark safe from non-doomed usage
insert @safeTeams
select distinct TeamID from Workitem_Now where ID not in (select doomed from @doomed)
except select safeTeam from @safeTeams

-- Doom entities not in safe list
insert @doomed
select ID from Team_Now
except select safeTeam from @safeTeams
```
**Examples:** Member (@safeMembers), Team (@safeTeams)

**Deletion pattern:** Same as first-party, but only doomed ones deleted

### Third-Party Entities (Never Purged - NULL REFERENCES)
**Pattern:** NULL out foreign keys, never doom or delete the entity
```sql
update Workitem_Now set ReleaseID=null from @doomed where doomed=ReleaseID
update Workitem set ReleaseID=null from @doomed where doomed=ReleaseID
```
**Examples:**
- **Release** (belongs to ValueStream, not Scope)
- **List values:** StatusID, CategoryID, PriorityID, ResolutionReasonID, TypeID, RiskID
- **Shared:** TimeboxID, EnvironmentID
- **Self-refs:** ParentID, SuperID, InReplyToID, DuplicateOfID

## Updating Scripts for Schema Changes

### When Schema Changes Between Versions

**1. Check git diff:**

**CRITICAL:** Use version branches **WITHOUT** the "v" prefix (e.g., `25.0`, not `v25.0`). The "v" prefix refers to tags, which may point to different commits. Always use branches for schema comparisons.

```bash
# Correct - use branches, save to file to ensure complete output
git diff 25.3 26.0 -- VersionOne.Domain/DataSchema.xsd > temp_diff.txt

# Verify branch format first
git branch -a | grep "25\." | sort -V

# Check line count to ensure diff exists
git diff 25.3 26.0 -- VersionOne.Domain/DataSchema.xsd | wc -l
```

**Common pitfall:** Terminal may truncate long diff output. Always save to file first and verify you see the complete changes.

**2. Identify entity type:**

**New First-Party Entity (has ScopeID):**
```sql
-- In "Rack 'em" phase:
-- doom [NewEntity] that live in doomed Scopes
insert @doomed
select ID from NewEntity_Now join @doomed on doomed=ScopeID

-- In "Stack 'em" phase:
raiserror('NewEntities', 0, 1) with nowait
delete NewEntity_Now from @doomed where doomed=ID
delete NewEntity from @doomed where doomed=ID
raiserror('%s NewEntities purged', 0, 1, @rowcount) with nowait
```

**New Third-Party Reference (no ScopeID, belongs elsewhere):**
```sql
-- In "Stack 'em" phase where entity is deleted:
update Entity_Now set NewEntityID=null from @doomed where doomed=NewEntityID
update Entity set NewEntityID=null from @doomed where doomed=NewEntityID
```

**New Second-Party (selective purging needed):**
```sql
-- Declare safe table at top:
declare @safeNewEntities table(safeNewEntity int not null primary key)

-- In "Rack 'em": Track safe instances
insert @safeNewEntities
select distinct NewEntityID from UsedBy_Now where ID not in (select doomed from @doomed)
except select safeNewEntity from @safeNewEntities

-- Doom unsafe instances
insert @doomed
select ID from NewEntity_Now
except select safeNewEntity from @safeNewEntities

-- In "Stack 'em": Delete as first-party
```

### Rules for Minimal Changes

1. **Clone existing patterns** - Find similar entity, copy approach
2. **Keep changes minimal** - Only add what's needed for new schema
3. **No extra validation** - Trust existing patterns
4. **Preserve order** - Add in same relative position as similar entities
5. **Match style exactly** - Whitespace, naming, error handling

## Common Patterns

### Many-to-Many Junction Tables
```sql
-- Delete from both sides
delete WorkitemGoals from @doomed where doomed=GoalID
delete WorkitemGoals from @doomed where doomed=WorkitemID
```

### Hierarchy Tables
```sql
delete WorkitemParentHierarchy from @doomed where doomed=AncestorID or doomed=DescendantID
```

### Nulling Foreign Keys
```sql
-- Always do _Now and history table
update Entity_Now set ForeignID=null from @doomed where doomed=ForeignID
update Entity set ForeignID=null from @doomed where doomed=ForeignID
```

### Error Handling
```sql
select @rowcount=@@ROWCOUNT, @error=@@ERROR; if @error<>0 goto ERR  -- For counted ops
select @error=@@ERROR; if @error<>0 goto ERR  -- For non-counted ops
```

## Version Management

### Creating New Version Script
1. Copy previous version: `cp PurgeProject-25.3.sql PurgeProject-26.0.sql`
2. Update version string (line ~19):
   ```sql
   declare @supportedVersion varchar(10); set @supportedVersion = '26.0'
   ```
3. Apply schema changes following patterns above
4. Test thoroughly on database with correct version

### Testing Checklist
- [ ] Version check works (rejects wrong version)
- [ ] SINGLE_USER mode activates
- [ ] Rollback works (default @commitChanges = null)
- [ ] All foreign key constraints satisfied
- [ ] EffectiveACL rebuilt correctly
- [ ] No orphaned records remain

## Key Principles

1. **Safety First:** Scripts default to ROLLBACK unless explicitly committed
2. **Order Matters:** Delete children before parents, junction tables before entities
3. **NULL Before Delete:** Always NULL foreign keys before deleting referenced entities
4. **Both Tables:** Handle both `_Now` views and history tables
5. **Minimal Changes:** Only add what schema changes require
6. **Follow Patterns:** Find similar entity, clone the approach exactly
