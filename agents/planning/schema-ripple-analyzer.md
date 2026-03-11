# Schema Ripple Analyzer

## When to Use
Run when data model changes are proposed — new fields, renamed fields, changed types, new tables, dropped columns. Maps the downstream impact across the workspace to identify everything that will break or need updating.

## Instructions

Given a set of proposed schema/data model changes, trace the impact through every crate layer.

### Ripple Tracing Steps

1. **Identify the changed type** — struct field added/removed/renamed, enum variant added/removed, table column changed.
2. **Find all consumers** — grep the workspace for every place the type is constructed, destructured, matched, or serialized.
3. **Assess impact per consumer**:
   - `struct` field addition: impacts all struct literal constructions (non-exhaustive structs avoid this)
   - `struct` field removal: impacts all field accesses and constructions
   - `enum` variant addition: impacts all `match` statements (non-exhaustive avoids compile errors, but logic may need updating)
   - Type change (e.g., `i32` → `i64`): impacts all assignments and comparisons
   - Rename: impacts all references
4. **Database migration impact** — identify if the change requires a migration and assess migration safety (additive vs destructive).
5. **Serialization impact** — if the type is `Serialize`/`Deserialize`, check for `#[serde(rename)]` that may affect JSON API compatibility.

### Migration Safety Classification

- **Safe (additive)**: new nullable column, new table, new index, new enum variant with `#[non_exhaustive]`
- **Requires backfill**: new NOT NULL column without default, column type widening
- **Destructive**: dropping a column, renaming a column without alias, changing column type narrowly
- **Breaking API change**: removing a struct field used in a JSON response, removing an enum variant

### Output Format

```yaml
change_summary:
  entity: User
  change_type: "added field: last_login_at: Option<DateTime<Utc>>"
  migration_safety: safe

affected_sites:
  - file: crates/auth-db/src/queries.rs
    line: 42
    impact: "INSERT query must include last_login_at column (use DEFAULT NULL)"
    severity: required_change

  - file: crates/auth-types/src/models.rs
    line: 15
    impact: "User struct gains new field; all struct-literal constructions will fail to compile"
    severity: compile_error
    recommendation: "Add #[non_exhaustive] to User struct, or update all construction sites"

  - file: crates/auth-api/src/handlers/users.rs
    line: 88
    impact: "UserResponse serialization now includes last_login_at — API contract change"
    severity: api_change
    recommendation: "Update OpenAPI spec and notify API consumers"

  - file: tests/integration/users.rs
    line: 201
    impact: "Test fixture constructs User struct literally — will fail to compile"
    severity: compile_error

migration_plan:
  up: "ALTER TABLE users ADD COLUMN last_login_at TIMESTAMPTZ;"
  down: "ALTER TABLE users DROP COLUMN last_login_at;"
  safety: safe
  notes: "Nullable column, no backfill required. Existing rows will have NULL."

summary:
  compile_errors: 2
  required_changes: 1
  api_changes: 1
  migration_required: true
  migration_safety: safe
```

## Tools
- Read
- Grep
- Glob

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:planning:schema-ripple-analyzer",
  prompt="Analyze the impact of adding last_login_at field to User struct. Workspace root: <path>"
)
```
