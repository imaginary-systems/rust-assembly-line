# Crate Integration Documenter

## When to Use
Run after implementing a story that introduces a new external crate dependency or a new cross-crate integration pattern within the workspace. Documents the integration for future crates to follow.

## Instructions

Review the new or changed `Cargo.toml` files and the code that uses new dependencies. Document how each new integration works.

### What to Document

**External Crate Integrations**
- A new external crate was added to the workspace for the first time
- A crate was used in a non-obvious way that required trial and error
- Feature flags were needed to make a crate work correctly
- A crate had footguns or gotchas that weren't obvious from its documentation

**Cross-Crate Workspace Integrations**
- A new dependency relationship was established between workspace crates
- A new `From`/`Into` conversion was needed between crate types
- A new trait was added to `crate:types` to enable a new cross-crate interaction
- A workspace-level Cargo feature flag was introduced

### Integration Document Format

Save to `docs/integrations/<crate-name>.md`:

```markdown
# Integration: <crate-name> v<version>

## What It Does
One paragraph on why this crate was chosen and what it provides.

## Workspace Location
- Used in: `crates/auth-db` (and any other crates)
- Cargo.toml entry: `crate-name = { version = "x.y", features = ["feature1"] }`

## Basic Usage Pattern
```rust
// Minimal working example of the integration
```

## Configuration
- Environment variables needed
- Compile-time features to enable
- Runtime initialization (e.g., connection pool setup)

## Testing
How to test code that uses this crate:
- Does it require a running service? (e.g., database, Redis)
- Is there a test feature or mock provided?
- What testcontainer image to use?

## Known Gotchas
- List of non-obvious behaviors, version-specific bugs, or footguns

## Version Pinning Notes
- Why the version is pinned (if not semver range)
- Any known incompatibilities with adjacent versions
```

### Output Format

```yaml
integrations_documented:
  - crate: sqlx
    version: "0.7"
    doc_file: docs/integrations/sqlx.md
    key_insight: "Use sqlx::test macro for per-test database isolation — each test gets a fresh migrated DB"
    gotchas:
      - "compile-time query verification requires DATABASE_URL at build time — use .env file or SQLX_OFFLINE=true"
      - "sqlx::FromRow with flatten requires #[sqlx(flatten)] on nested struct fields"

  - crate: testcontainers
    version: "0.15"
    doc_file: docs/integrations/testcontainers.md
    key_insight: "Spin up a real Postgres container per test binary — much faster than per-test"

workspace_integration_changes:
  - description: "auth-types now exports UserFromRow conversion trait used by auth-db"
    doc_file: docs/integrations/workspace/auth-types-auth-db-conversion.md

nothing_new: false
```

## Tools
- Read
- Grep
- Glob
- Write

## Example Usage

```
Task(
  subagent_type="rust-assembly-line:compound:crate-integration-documenter",
  prompt="Document new crate integrations from this session. Workspace: <path>"
)
```
